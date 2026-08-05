#!/usr/bin/env bash
set -euo pipefail

# Defaults to the tracked source rather than the installed copy, so the tests
# exercise what is in the repo. Override to test an installed script:
#   SCRIPT=~/.local/bin/update-llama-cpp tests/test-update.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT=${SCRIPT:-$HERE/../home/profiles/bazzite/.local/bin/update-llama-cpp}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_release() {
  local repo=$1 tag=$2 broken=${3:-false}
  local device=${4:-Vulkan0: Fake Vulkan}

  if [[ $broken == true ]]; then
    cat >"$repo/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(broken NONE)
message(FATAL_ERROR "intentional candidate build failure")
CMAKE
  else
    cat >"$repo/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(fake_llama LANGUAGES CXX)
add_executable(llama-server main.cpp)
add_executable(llama-cli main.cpp)
add_executable(llama-bench main.cpp)
add_custom_target(unrelated ALL COMMAND ${CMAKE_COMMAND} -E false)
set_target_properties(llama-server llama-cli llama-bench PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
CMAKE
    cat >"$repo/main.cpp" <<CPP
#include <spirv/unified1/spirv.hpp>
#include <iostream>
int main() { std::cout << "${device} ${tag}\\n"; return 0; }
CPP
  fi

  git -C "$repo" add CMakeLists.txt main.cpp 2>/dev/null || git -C "$repo" add CMakeLists.txt
  git -C "$repo" commit -q -m "$tag"
  git -C "$repo" tag "$tag"
}

run_updater() {
  env \
    LLAMA_CPP_ROOT="${TEST_ROOT:-$TMP/install}" \
    LLAMA_REPO_URL="$TMP/upstream" \
    LLAMA_SKIP_BREW=1 \
    LLAMA_RESTART="${TEST_RESTART:-0}" \
    LLAMA_HEALTH_ATTEMPTS=1 \
    LLAMA_VULKAN_INCLUDE_DIR="$TMP/include" \
    LLAMA_SPIRV_INCLUDE_DIR="$TMP/spirv/include" \
    LLAMA_VULKAN_LIBRARY="$TMP/libvulkan.so" \
    LLAMA_CMAKE_PREFIX_PATH="$TMP/prefix" \
    LLAMA_SYSTEMCTL_BIN="$TMP/bin/systemctl" \
    LLAMA_CURL_BIN="$TMP/bin/curl" \
    FAKE_UNIT_EXISTS="${TEST_UNIT_EXISTS:-0}" \
    FAKE_HEALTH="${TEST_HEALTH:-ok}" \
    FAKE_ACTION_LOG="$TMP/service-actions" \
    "$SCRIPT"
}

mkdir -p "$TMP/bin"
cat >"$TMP/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
case ${2:-} in
  cat) [[ ${FAKE_UNIT_EXISTS:-0} == 1 ]] ;;
  restart|stop) printf '%s\n' "$2" >>"$FAKE_ACTION_LOG" ;;
esac
SYSTEMCTL
cat >"$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
if [[ ${FAKE_HEALTH:-ok} == term ]]; then
  kill -TERM "$PPID"
  exit 1
fi
[[ ${FAKE_HEALTH:-ok} == ok ]]
CURL
chmod +x "$TMP/bin/systemctl" "$TMP/bin/curl"

mkdir -p "$TMP/spirv/include/spirv/unified1"
printf '#pragma once\n' >"$TMP/spirv/include/spirv/unified1/spirv.hpp"

git init -q "$TMP/upstream"
git -C "$TMP/upstream" config user.name test
git -C "$TMP/upstream" config user.email test@example.invalid
make_release "$TMP/upstream" b100
make_release "$TMP/upstream" b200
git -C "$TMP/upstream" tag not-a-release

run_updater
[[ -L "$TMP/install/current" ]] || fail 'current symlink was not created'
[[ $(basename "$(readlink -f "$TMP/install/current")") == b200 ]] || fail 'newest numbered tag was not activated'
[[ -x "$TMP/install/current/build/bin/llama-server" ]] || fail 'llama-server was not built'
[[ -x "$TMP/install/current/build/bin/llama-bench" ]] || fail 'llama-bench was not built'

touch "$TMP/install/current/preserve-on-noop"
run_updater
[[ -e "$TMP/install/current/preserve-on-noop" ]] || fail 'unchanged release was rebuilt'
mkdir -p "$TMP/install/releases/b050" "$TMP/install/releases/b150"
touch "$TMP/install/releases/b050/.approved" "$TMP/install/releases/b150/.approved"
run_updater
shopt -s nullglob
retained=("$TMP/install/releases"/b*)
shopt -u nullglob
[[ ${#retained[@]} -eq 2 ]] || fail 'release pruning did not converge to two releases'
[[ -d "$TMP/install/releases/b150" ]] || fail 'newest approved fallback was not retained'
[[ ! -e "$TMP/install/releases/b050" ]] || fail 'old approved fallback was not pruned'
mkdir -p "$TMP/real-root"
ln -s "$TMP/real-root" "$TMP/root-link"
TEST_ROOT="$TMP/root-link" run_updater
touch "$TMP/real-root/current/preserve-through-symlink"
TEST_ROOT="$TMP/root-link" run_updater
[[ -e "$TMP/real-root/current/preserve-through-symlink" ]] || fail 'symlinked root caused active release rebuild'

TEST_ROOT="$TMP/recovery-root" run_updater
rm "$TMP/recovery-root/current/.approved"
: >"$TMP/service-actions"
if TEST_ROOT="$TMP/recovery-root" TEST_RESTART=1 TEST_UNIT_EXISTS=1 TEST_HEALTH=fail run_updater; then
  fail 'unapproved interrupted activation unexpectedly succeeded'
fi
[[ ! -e "$TMP/recovery-root/current" ]] || fail 'unapproved failed recovery remained active'
[[ ! -e "$TMP/recovery-root/releases/b200" ]] || fail 'unapproved failed recovery candidate was retained'
mapfile -t service_actions <"$TMP/service-actions"
[[ ${service_actions[*]} == 'restart stop' ]] || fail 'unapproved failed recovery did not stop managed server'



make_release "$TMP/upstream" b250 false 'CPU0: Fake CPU'
if run_updater; then
  fail 'candidate without a Vulkan device unexpectedly succeeded'
fi
[[ $(basename "$(readlink -f "$TMP/install/current")") == b200 ]] || fail 'non-Vulkan candidate replaced current release'
[[ ! -e "$TMP/install/releases/b250" ]] || fail 'non-Vulkan candidate directory was not removed'

make_release "$TMP/upstream" b275
: >"$TMP/service-actions"
if TEST_RESTART=1 TEST_UNIT_EXISTS=1 TEST_HEALTH=fail run_updater; then
  fail 'health-rejected candidate unexpectedly succeeded'
fi
[[ $(basename "$(readlink -f "$TMP/install/current")") == b200 ]] || fail 'health-rejected candidate replaced current release'
[[ ! -e "$TMP/install/releases/b275" ]] || fail 'health-rejected candidate directory was not removed'
mapfile -t service_actions <"$TMP/service-actions"
[[ ${service_actions[*]} == 'restart restart' ]] || fail 'health rollback did not restart new then old release'

make_release "$TMP/upstream" b280
: >"$TMP/service-actions"
if TEST_RESTART=1 TEST_UNIT_EXISTS=1 TEST_HEALTH=term run_updater; then
  fail 'interrupted activation unexpectedly succeeded'
fi
[[ $(basename "$(readlink -f "$TMP/install/current")") == b200 ]] || fail 'interrupted activation did not restore current release'
[[ ! -e "$TMP/install/releases/b280" ]] || fail 'interrupted candidate directory was not removed'
mapfile -t service_actions <"$TMP/service-actions"
[[ ${service_actions[*]} == 'restart restart' ]] || fail 'interrupted activation did not restart old release'

make_release "$TMP/upstream" b290
: >"$TMP/service-actions"
if TEST_ROOT="$TMP/install-new" TEST_RESTART=1 TEST_UNIT_EXISTS=1 TEST_HEALTH=fail run_updater; then
  fail 'first health-rejected candidate unexpectedly succeeded'
fi
[[ ! -e "$TMP/install-new/current" ]] || fail 'failed first activation left a current release'
[[ ! -e "$TMP/install-new/releases/b290" ]] || fail 'failed first candidate directory was not removed'
mapfile -t service_actions <"$TMP/service-actions"
[[ ${service_actions[*]} == 'restart stop' ]] || fail 'failed first activation did not stop managed server'

make_release "$TMP/upstream" b300 true
if run_updater; then
  fail 'broken candidate unexpectedly succeeded'
fi
[[ $(basename "$(readlink -f "$TMP/install/current")") == b200 ]] || fail 'broken candidate replaced current release'
[[ ! -e "$TMP/install/releases/b300" ]] || fail 'broken candidate directory was not removed'

make_release "$TMP/upstream" b310
date +%s >"$TMP/install/.last-build"
LLAMA_MIN_INTERVAL=604800 run_updater
[[ $(basename "$(readlink -f "$TMP/install/current")") == b200 ]] || fail 'minimum build interval did not block a new release'
[[ ! -e "$TMP/install/releases/b310" ]] || fail 'minimum build interval still cloned a candidate'

printf '%s\n' 0 >"$TMP/install/.last-build"
LLAMA_MIN_INTERVAL=604800 run_updater
[[ $(basename "$(readlink -f "$TMP/install/current")") == b310 ]] || fail 'elapsed build interval did not permit a build'
(($(<"$TMP/install/.last-build") > 0)) || fail 'successful build did not refresh the build stamp'

printf 'PASS: updater selects, preserves, and rolls back releases\n'

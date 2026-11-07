#!/usr/bin/env bash
set -euo pipefail

# Runs cgroup-metrics --once against a fake cgroup tree. Defaults to the
# tracked source; override with SCRIPT=~/.local/bin/cgroup-metrics.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT=${SCRIPT:-$HERE/../home/profiles/bazzite/.local/bin/cgroup-metrics}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

user=user.slice/user-1000.slice/user@1000.service
cg() { # cg <relative dir> <usage_usec> <memory.current> [io.stat line]
  local d=$TMP/root/$1
  mkdir -p "$d"
  printf 'usage_usec %s\nuser_usec 1\nsystem_usec 1\n' "$2" >"$d/cpu.stat"
  printf '%s\n' "$3" >"$d/memory.current"
  printf '0\n' >"$d/memory.swap.current"
  printf '7\n' >"$d/pids.current"
  [[ -n ${4:-} ]] && printf '%s\n' "$4" >"$d/io.stat"
  return 0
}

cg "$user/app.slice/app-flatpak-com.rtosta.zapzap-2133410822.scope" 2500000 1048576 \
  '259:0 rbytes=100 wbytes=20 rios=1 wios=1 dbytes=0 dios=0'
cg "$user/app.slice/app-flatpak-com.rtosta.zapzap-2754307238.scope" 500000 2048
cg "$user/app.slice/app-steam@autostart.service" 1000000 4096
cg "$user/app.slice/app-org.kde.konsole@4c2c1f6b4b1f4f8e9a7d1e2f3a4b5c6d.service" 1 1
cg "$user/app.slice/dbus-:1.3-org.kde.kwalletd6@0.service" 1 1
cg "$user/session.slice/plasma-kwin_wayland.service" 1 1
cg "system.slice/systemd-journald.service" 1 1
cg 'system.slice/system-getty.slice' 1 1
# A pids.current of "max"-style garbage and a missing io.stat must not break it.
printf 'max\n' >"$TMP/root/system.slice/systemd-journald.service/pids.current"

out=$TMP/out/cgroup.prom
CGROUP_ROOT=$TMP/root CGROUP_METRICS_UID=1000 CGROUP_METRICS_OUT=$out python3 -I "$SCRIPT" --once
[[ -s $out ]] || fail "no output written"
[[ ! -e $out.tmp ]] || fail "temp file left behind"

expect() {
  grep -qxF -- "$1" "$out" || { cat "$out" >&2; fail "missing line: $1"; }
}
z='slice="app",app="com.rtosta.zapzap"'
expect "cgroup_cpu_usage_seconds_total{$z,unit=\"app-flatpak-com.rtosta.zapzap-2133410822.scope\"} 2.5"
expect "cgroup_cpu_usage_seconds_total{$z,unit=\"app-flatpak-com.rtosta.zapzap-2754307238.scope\"} 0.5"
expect "cgroup_io_read_bytes_total{$z,unit=\"app-flatpak-com.rtosta.zapzap-2133410822.scope\"} 100"
expect "cgroup_io_write_bytes_total{$z,unit=\"app-flatpak-com.rtosta.zapzap-2133410822.scope\"} 20"
expect "cgroup_memory_bytes{$z,unit=\"app-flatpak-com.rtosta.zapzap-2133410822.scope\"} 1048576"
expect 'cgroup_cpu_usage_seconds_total{slice="app",app="steam",unit="app-steam@autostart.service"} 1.0'
# Large counters keep sub-second precision.
cg "$user/app.slice/app-big-1.scope" 972002778123 1
CGROUP_ROOT=$TMP/root CGROUP_METRICS_UID=1000 CGROUP_METRICS_OUT=$out python3 -I "$SCRIPT" --once
expect 'cgroup_cpu_usage_seconds_total{slice="app",app="big",unit="app-big-1.scope"} 972002.778123'
expect 'cgroup_tasks{slice="app",app="org.kde.konsole",unit="app-org.kde.konsole@4c2c1f6b4b1f4f8e9a7d1e2f3a4b5c6d.service"} 7'
expect 'cgroup_memory_bytes{slice="app",app="org.kde.kwalletd6",unit="dbus-:1.3-org.kde.kwalletd6@0.service"} 1'
expect 'cgroup_memory_bytes{slice="session",app="plasma-kwin_wayland",unit="plasma-kwin_wayland.service"} 1'
expect 'cgroup_memory_bytes{slice="system",app="system-getty",unit="system-getty.slice"} 1'
if grep -q 'cgroup_tasks{slice="system",app="systemd-journald"' "$out"; then
  fail "unparseable pids.current should be skipped"
fi
# A cgroup without io.stat gets no io series, rather than a zero.
if grep -q 'cgroup_io_read_bytes_total{slice="app",app="steam"' "$out"; then
  fail "missing io.stat should produce no io series"
fi
grep -q '^# TYPE cgroup_cpu_usage_seconds_total counter$' "$out" || fail "missing TYPE line"

# The real tree on this host, when there is one: must parse and find something.
if [[ -d /sys/fs/cgroup/system.slice ]]; then
  CGROUP_METRICS_OUT=$TMP/real.prom python3 -I "$SCRIPT" --once
  grep -q '^cgroup_cpu_usage_seconds_total{slice="system"' "$TMP/real.prom" || fail "real tree: no system.slice series"
fi

echo "ok"

#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_DIR="$HERE/home"
VSCODE_EXTENSIONS_FILE="$HERE/manifests/vscode-extensions.txt"

usage() {
  cat <<'USAGE'
Usage: ./bootstrap.sh

Debian 11/12+ bootstrap for devcontainer and personal machine environments.
USAGE
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
fi

run() {
  printf '>'; printf ' %q' "$@"; echo
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

SUDO=()
if [[ ${EUID} -ne 0 ]] && have sudo; then
  SUDO=(sudo)
fi

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"

resolve_user_home() {
  local user="$1"
  local home=""
  if have getent; then
    home="$(getent passwd "$user" | cut -d: -f6)"
  fi
  if [[ -z "$home" ]]; then
    home="${HOME:-}"
  fi
  echo "$home"
}

TARGET_HOME="$(resolve_user_home "$TARGET_USER")"

run_as_target_user() {
  if [[ "$(id -un)" == "$TARGET_USER" ]]; then
    run env HOME="$TARGET_HOME" "$@"
    return $?
  fi

  if have sudo; then
    run sudo -u "$TARGET_USER" -H env HOME="$TARGET_HOME" "$@"
    return $?
  fi

  if have su; then
    run su - "$TARGET_USER" -s /bin/sh -c "$(printf '%q ' "$@")"
    return $?
  fi

  echo "Cannot run as $TARGET_USER: neither sudo nor su is available"
  return 1
}

capture_as_target_user() {
  if [[ "$(id -un)" == "$TARGET_USER" ]]; then
    env HOME="$TARGET_HOME" "$@"
    return $?
  fi

  if have sudo; then
    sudo -u "$TARGET_USER" -H env HOME="$TARGET_HOME" "$@"
    return $?
  fi

  if have su; then
    su - "$TARGET_USER" -s /bin/sh -c "$(printf '%q ' "$@")"
    return $?
  fi

  echo "Cannot run as $TARGET_USER: neither sudo nor su is available" >&2
  return 1
}

require_apt() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "This bootstrap only supports Linux."
    exit 1
  fi

  if ! have apt-get; then
    echo "This bootstrap expects Debian 11/12+ with apt-get available."
    exit 1
  fi
}

pm_update() {
  run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -y
}

pm_install() {
  run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

map_pkg() {
  local tool="$1"
  case "$tool" in
    zsh)             echo zsh ;;
    starship)        echo starship ;;
    eza)             echo eza ;;
    rg)              echo ripgrep ;;
    fzf)             echo fzf ;;
    fd)              echo fd-find ;;
    bat)             echo bat ;;
    jq)              echo jq ;;
    delta)           echo git-delta ;;
    git)             echo git ;;
    curl)            echo curl ;;
    rsync)           echo rsync ;;
    ca-certificates) echo ca-certificates ;;
    tar)             echo tar ;;
    xz)              echo xz-utils ;;
    direnv)          echo direnv ;;
    atuin)           echo atuin ;;
    zoxide)          echo zoxide ;;
    ug)              echo ugrep ;;
    *) echo "" ;;
  esac
}

ensure_fd_shim() {
  if ! have fd && have fdfind; then
    run mkdir -p "$TARGET_HOME/.local/bin"
    cat > "$TARGET_HOME/.local/bin/fd" <<'SHIM'
#!/usr/bin/env bash
exec fdfind "$@"
SHIM
    run chmod +x "$TARGET_HOME/.local/bin/fd"
  fi
}

# Downloads a binary from a GitHub release asset.
# Usage: gh_release <owner/repo> <asset-pattern> <binary-name>
gh_release() {
  local repo="$1" pattern="$2" binary="$3"
  local url

  url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | grep "browser_download_url" \
    | grep -E "$pattern" \
    | grep -vE "\.(sha256|sha512|asc|sig|sbom)$" \
    | head -1 \
    | cut -d '"' -f 4)

  if [[ -z "$url" ]]; then
    echo "  ⚠ could not resolve release URL for $repo ($pattern)" >&2
    return 1
  fi

  local tmp
  tmp=$(mktemp -d)

  curl -fsSL "$url" -o "$tmp/asset" || { rm -rf "$tmp"; return 1; }

  case "$url" in
    *.tar.gz) tar -xzf "$tmp/asset" -C "$tmp" ;;
    *.zip)    unzip -q "$tmp/asset" -d "$tmp" ;;
    *)        cp "$tmp/asset" "$tmp/$binary" ;;
  esac

  find "$tmp" -name "$binary" -type f | head -1 \
    | xargs -I{} install -m755 {} "$TARGET_HOME/.local/bin/$binary"
  rm -rf "$tmp"
  echo "  ✓ $binary"
}

install_gh_tools() {
  local arch
  arch="$(uname -m)"

  run mkdir -p "$TARGET_HOME/.local/bin"

  gh_release "chmln/sd"    "${arch}-unknown-linux-gnu.tar.gz"  "sd"   || true
  gh_release "casey/just"  "${arch}-unknown-linux-musl.tar.gz" "just" || true

  # yq — direct binary (no archive)
  local yq_arch
  case "$arch" in
    x86_64)  yq_arch="amd64" ;;
    aarch64) yq_arch="arm64" ;;
    *)       yq_arch="$arch" ;;
  esac
  if curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}" \
      -o "$TARGET_HOME/.local/bin/yq"; then
    chmod +x "$TARGET_HOME/.local/bin/yq"
    echo "  ✓ yq"
  else
    echo "  ⚠ failed to install yq" >&2
  fi
}

install_oh_my_zsh() {
  if [[ -d "$TARGET_HOME/.oh-my-zsh" ]]; then
    return 0
  fi
  if ! have curl; then
    echo "Skipping oh-my-zsh install: curl missing"
    return 0
  fi

  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true
}

install_starship_fallback() {
  if have starship; then
    return 0
  fi
  if ! have curl; then
    echo "Skipping starship fallback: curl missing"
    return 0
  fi

  run mkdir -p "$TARGET_HOME/.local/bin"
  run sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- -y -b "$TARGET_HOME/.local/bin" || true
}

install_atuin_fallback() {
  if have atuin; then
    return 0
  fi
  if ! have curl; then
    echo "Skipping atuin fallback: curl missing"
    return 0
  fi

  run_as_target_user bash -c "$(curl -fsSL https://setup.atuin.sh)" || echo "Warning: failed to install atuin"

  if [[ -x "$TARGET_HOME/.atuin/bin/atuin" ]] && [[ ! -e "$TARGET_HOME/.local/bin/atuin" ]]; then
    run mkdir -p "$TARGET_HOME/.local/bin"
    run ln -sf "$TARGET_HOME/.atuin/bin/atuin" "$TARGET_HOME/.local/bin/atuin"
  fi
}

install_or_update_git_repo() {
  local repo_url="$1"
  local dest_dir="$2"

  if [[ -d "$dest_dir/.git" ]]; then
    run git -C "$dest_dir" pull --ff-only || true
    return 0
  fi

  if [[ -d "$dest_dir" ]]; then
    echo "Skipping repo sync for $dest_dir: directory exists but is not a git repo"
    return 0
  fi

  run mkdir -p "$(dirname "$dest_dir")"
  run git clone --depth 1 "$repo_url" "$dest_dir" || true
}

install_zsh_plugins() {
  if ! have git; then
    echo "Skipping zsh plugin install: git missing"
    return 0
  fi

  install_or_update_git_repo \
    "https://github.com/zsh-users/zsh-autosuggestions" \
    "$TARGET_HOME/.zsh/zsh-autosuggestions"

  install_or_update_git_repo \
    "https://github.com/zsh-users/zsh-syntax-highlighting" \
    "$TARGET_HOME/.zsh/zsh-syntax-highlighting"
}

install_vscode_extensions() {
  if [[ ! -f "$VSCODE_EXTENSIONS_FILE" ]]; then
    return 0
  fi

  local cmd=""
  if have code; then
    cmd="code"
  elif have code-server; then
    cmd="code-server"
  elif [[ -x "/tmp/vscode-web/bin/code-server" ]]; then
    cmd="/tmp/vscode-web/bin/code-server"
  else
    echo "Skipping VS Code extension install: 'code' or 'code-server' not found"
    return 0
  fi

  local ext
  while IFS= read -r ext || [[ -n "$ext" ]]; do
    [[ -z "${ext// }" ]] && continue
    [[ "$ext" =~ ^[[:space:]]*# ]] && continue
    ext="${ext%@*}"
    [[ -z "$ext" ]] && continue
    "$cmd" --install-extension "$ext" >/dev/null 2>&1 || true
  done < "$VSCODE_EXTENSIONS_FILE"
}

sync_vscode_web_settings() {
  local source_settings="$TARGET_HOME/.config/Code/User/settings.json"
  if [[ ! -f "$source_settings" ]]; then
    return 0
  fi

  local targets=(
    "$TARGET_HOME/.local/share/code-server/User/settings.json"
    "$TARGET_HOME/.local/share/code-server/Machine/settings.json"
    "$TARGET_HOME/.vscode-server/data/Machine/settings.json"
    "$TARGET_HOME/.vscode-server/data/User/settings.json"
  )

  local target
  for target in "${targets[@]}"; do
    run mkdir -p "$(dirname "$target")"
    run cp "$source_settings" "$target"
  done
}

set_default_shell_to_zsh() {
  local zsh_bin
  zsh_bin="$(command -v zsh || true)"
  if [[ -z "$zsh_bin" ]]; then
    echo "Skipping default shell change: zsh not found"
    return 0
  fi

  local current_shell=""
  if have getent; then
    current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
  fi
  if [[ -z "$current_shell" ]]; then
    current_shell="${SHELL:-}"
  fi
  if [[ "$current_shell" == "$zsh_bin" ]]; then
    return 0
  fi

  if ! have chsh; then
    echo "Skipping default shell change: chsh missing"
    return 0
  fi

  if [[ ${#SUDO[@]} -gt 0 ]]; then
    run "${SUDO[@]}" chsh -s "$zsh_bin" "$TARGET_USER" || run chsh -s "$zsh_bin" "$TARGET_USER" || true
  else
    run chsh -s "$zsh_bin" "$TARGET_USER" || true
  fi
}

install_packages() {
  require_apt
  pm_update
  local tools=(zsh starship eza rg fzf fd bat jq delta git curl rsync ca-certificates tar xz direnv atuin zoxide ug)
  local pkgs=()
  local seen=":"
  local mapped
  for t in "${tools[@]}"; do
    mapped="$(map_pkg "$t")"
    if [[ -n "$mapped" ]] && [[ "$seen" != *":$mapped:"* ]]; then
      pkgs+=("$mapped")
      seen+="$mapped:"
    fi
  done

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    local pkg
    for pkg in "${pkgs[@]}"; do
      if ! pm_install "$pkg"; then
        echo "Warning: failed to install package '$pkg' via apt; continuing"
      fi
    done
  fi

  ensure_fd_shim
  install_starship_fallback
  install_atuin_fallback
  install_oh_my_zsh
  install_zsh_plugins
  set_default_shell_to_zsh
}

install_gh() {
  if have gh; then
    return 0
  fi
  if ! have curl || ! have jq; then
    echo "Skipping gh install: curl or jq missing"
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Skipping gh install: unsupported arch $(uname -m)"; return 0 ;;
  esac

  local version
  version="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
    | jq -r '.tag_name | ltrimstr("v")' 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    echo "Warning: could not determine latest gh version; skipping"
    return 0
  fi

  local tmp_deb
  tmp_deb="$(mktemp /tmp/gh_XXXXXX.deb)"
  if curl -fsSL -o "$tmp_deb" \
    "https://github.com/cli/cli/releases/download/v${version}/gh_${version}_linux_${arch}.deb"; then
    run "${SUDO[@]}" dpkg -i "$tmp_deb" || true
  else
    echo "Warning: failed to download gh v${version}"
  fi
  rm -f "$tmp_deb"
}

install_glab() {
  if have glab; then
    return 0
  fi
  if ! have curl || ! have jq; then
    echo "Skipping glab install: curl or jq missing"
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Skipping glab install: unsupported arch $(uname -m)"; return 0 ;;
  esac

  local version
  version="$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases" \
    | jq -r '.[0].tag_name | ltrimstr("v")' 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    echo "Warning: could not determine latest glab version; skipping"
    return 0
  fi

  local tmp_deb
  tmp_deb="$(mktemp /tmp/glab_XXXXXX.deb)"
  if curl -fsSL -o "$tmp_deb" \
    "https://gitlab.com/gitlab-org/cli/-/releases/v${version}/downloads/glab_${version}_linux_${arch}.deb"; then
    run "${SUDO[@]}" dpkg -i "$tmp_deb" || true
  else
    echo "Warning: failed to download glab v${version}"
  fi
  rm -f "$tmp_deb"
}

install_acli() {
  if have acli; then
    return 0
  fi
  if ! have curl; then
    echo "Skipping acli install: curl missing"
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Skipping acli install: unsupported arch $(uname -m)"; return 0 ;;
  esac

  run mkdir -p "$TARGET_HOME/.local/bin"
  if curl -fsSL -o "$TARGET_HOME/.local/bin/acli" \
    "https://acli.atlassian.com/linux/latest/acli_linux_${arch}/acli"; then
    run chmod +x "$TARGET_HOME/.local/bin/acli"
  else
    echo "Warning: failed to download Atlassian CLI"
    rm -f "$TARGET_HOME/.local/bin/acli"
  fi
}

install_zellij() {
  if have zellij; then
    return 0
  fi
  if ! have curl || ! have tar; then
    echo "Skipping zellij install: curl or tar missing"
    return 0
  fi

  local arch target
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) target="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) target="aarch64-unknown-linux-musl" ;;
    *) echo "Skipping zellij install: unsupported arch $arch"; return 0 ;;
  esac

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/zellij_XXXXXX)"
  if curl -fsSL -o "$tmp_dir/zellij.tar.gz" \
    "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${target}.tar.gz" \
    && tar -xzf "$tmp_dir/zellij.tar.gz" -C "$tmp_dir"; then
    run mkdir -p "$TARGET_HOME/.local/bin"
    run install -m 0755 "$tmp_dir/zellij" "$TARGET_HOME/.local/bin/zellij"
  else
    echo "Warning: failed to install zellij"
  fi
  rm -rf "$tmp_dir"
}

install_kubectl() {
  if have kubectl; then
    return 0
  fi
  if ! have curl; then
    echo "Skipping kubectl install: curl missing"
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Skipping kubectl install: unsupported arch $(uname -m)"; return 0 ;;
  esac

  local version
  version="$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    echo "Warning: could not determine latest kubectl version; skipping"
    return 0
  fi

  run mkdir -p "$TARGET_HOME/.local/bin"
  if curl -fsSL -o "$TARGET_HOME/.local/bin/kubectl" \
    "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"; then
    run chmod +x "$TARGET_HOME/.local/bin/kubectl"
  else
    echo "Warning: failed to download kubectl ${version}"
    rm -f "$TARGET_HOME/.local/bin/kubectl"
  fi
}

install_uv() {
  if have uv; then
    return 0
  fi
  if ! have curl; then
    echo "Skipping uv install: curl missing"
    return 0
  fi

  run_as_target_user bash -c "$(curl -LsSf https://astral.sh/uv/install.sh)" || \
    echo "Warning: failed to install uv"
}

install_bun() {
  if have bun; then
    return 0
  fi
  if ! have curl; then
    echo "Skipping bun install: curl missing"
    return 0
  fi

  pm_install unzip  # required by the bun installer on Linux
  run_as_target_user bash -c "$(curl -LsSf https://bun.sh/install)" || \
    echo "Warning: failed to install bun"
}

ensure_node_and_npm() {
  local missing_pkgs=()

  if ! have node; then
    missing_pkgs+=(nodejs)
  fi
  if ! have npm; then
    missing_pkgs+=(npm)
  fi

  if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
    return 0
  fi

  local pkg
  for pkg in "${missing_pkgs[@]}"; do
    if ! pm_install "$pkg"; then
      echo "Warning: failed to install package '$pkg' via apt; continuing"
    fi
  done
}

configure_npm_and_ai_tools() {
  if ! have npm; then
    echo "Skipping npm/AI tools: npm not found"
    return 0
  fi

  local desired_prefix="$TARGET_HOME/.npm-global"
  local current_prefix=""
  current_prefix="$(capture_as_target_user npm config get prefix 2>/dev/null || true)"
  current_prefix="${current_prefix//$'\n'/}"

  if [[ "$current_prefix" != "$desired_prefix" ]]; then
    run mkdir -p "$desired_prefix"
    if ! run_as_target_user npm config set prefix "$desired_prefix" --location=user; then
      echo "Warning: failed to set npm user prefix to $desired_prefix"
    fi
  fi

  if ! capture_as_target_user npm list -g --depth=0 @openai/codex >/dev/null 2>&1; then
    if ! run_as_target_user npm install -g @openai/codex; then
      echo "Warning: failed to install @openai/codex globally"
    fi
  fi

  # Claude Code — official installer
  if ! have claude; then
    curl -fsSL https://claude.ai/install.sh | bash || \
      echo "Warning: failed to install claude"
  fi

  # opencode
  if ! have opencode; then
    curl -fsSL https://opencode.ai/install | bash || \
      echo "Warning: failed to install opencode"
  fi
}

sync_rootfs() {
  if [[ ! -d "$ROOTFS_DIR" ]]; then
    echo "Missing home directory: $ROOTFS_DIR"
    exit 1
  fi

  run mkdir -p "$TARGET_HOME"

  if have rsync; then
    run rsync -a "$ROOTFS_DIR/" "$TARGET_HOME/"
  else
    run cp -R "$ROOTFS_DIR/." "$TARGET_HOME/"
  fi
}

main() {
  install_packages
  install_gh_tools
  install_gh
  install_glab
  install_acli
  install_zellij
  install_kubectl
  install_uv
  install_bun
  ensure_node_and_npm
  configure_npm_and_ai_tools
  sync_rootfs
  sync_vscode_web_settings
  install_vscode_extensions

  echo "Bootstrap complete. Start a new shell session to load zsh/starship changes."
}

main "$@"

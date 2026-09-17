# rustup is keg-only on macOS, so its cargo/rustc proxies aren't symlinked into
# the brew prefix; put the keg bin on PATH directly. (~/.cargo/bin is handled in
# base 10-path.zsh.)
if [ -d /opt/homebrew/opt/rustup/bin ]; then
  case ":$PATH:" in
    *":/opt/homebrew/opt/rustup/bin:"*) ;;
    *) export PATH="/opt/homebrew/opt/rustup/bin:$PATH" ;;
  esac
fi

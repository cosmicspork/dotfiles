if [ -d /Applications/Docker.app/Contents/Resources/bin ]; then
  case ":$PATH:" in
    *":/Applications/Docker.app/Contents/Resources/bin:"*) ;;
    *) export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH" ;;
  esac
fi

# rustup is keg-only on macOS, so its cargo/rustc proxies aren't symlinked into
# the brew prefix; put the keg bin on PATH directly. (~/.cargo/bin is handled in
# base 10-path.zsh.)
if [ -d /opt/homebrew/opt/rustup/bin ]; then
  case ":$PATH:" in
    *":/opt/homebrew/opt/rustup/bin:"*) ;;
    *) export PATH="/opt/homebrew/opt/rustup/bin:$PATH" ;;
  esac
fi

# Docker Desktop ships completions outside fpath; Oh My Zsh already ran compinit,
# so re-run it after extending fpath or the completions never load.
if [ -d "$HOME/.docker/completions" ]; then
  fpath=("$HOME/.docker/completions" $fpath)
  autoload -Uz compinit
  compinit
fi

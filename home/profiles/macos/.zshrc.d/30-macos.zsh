if [ -d /Applications/Docker.app/Contents/Resources/bin ]; then
  case ":$PATH:" in
    *":/Applications/Docker.app/Contents/Resources/bin:"*) ;;
    *) export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH" ;;
  esac
fi

# Docker Desktop ships completions outside fpath; Oh My Zsh already ran compinit,
# so re-run it after extending fpath or the completions never load.
if [ -d "$HOME/.docker/completions" ]; then
  fpath=("$HOME/.docker/completions" $fpath)
  autoload -Uz compinit
  compinit
fi

# Hand off interactive bash sessions to zsh if available.
# This keeps terminals consistent even when the launcher uses bash.
case $- in
  *i*) ;;
  *) return ;;
esac

if command -v zsh >/dev/null 2>&1 && [ -z "${ZSH_VERSION:-}" ]; then
  exec zsh -l
fi

# Bash fallback config (only reached if zsh is unavailable)

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.npm-global/bin:"*) ;;
  *) export PATH="$HOME/.npm-global/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.config/composer/vendor/bin:"*) ;;
  *) export PATH="$HOME/.config/composer/vendor/bin:$PATH" ;;
esac

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi

if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER="delta"
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza'
  alias ll='eza -l --group --git'
  alias la='eza -la --group --git'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never'
fi

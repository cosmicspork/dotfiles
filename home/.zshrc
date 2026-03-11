# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="" # Disabled — using Starship
plugins=(
    git
    sudo
)

if [ -d "$ZSH" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# Autosuggestions
if [ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v hx >/dev/null 2>&1; then
  export SUDO_EDITOR="hx"
  export EDITOR="hx"
fi

case ":$PATH:" in
  *":$HOME/.npm-global/bin:"*) ;;
  *) export PATH="$HOME/.npm-global/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.config/composer/vendor/bin:"*) ;;
  *) export PATH="$HOME/.config/composer/vendor/bin:$PATH" ;;
esac

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
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

# Syntax highlighting (must be last)
if [ -f "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

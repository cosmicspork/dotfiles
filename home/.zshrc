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

case ":$PATH:" in
  *":$HOME/.npm-global/bin:"*) ;;
  *) export PATH="$HOME/.npm-global/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.bun/bin:"*) ;;
  *) export PATH="$HOME/.bun/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.config/composer/vendor/bin:"*) ;;
  *) export PATH="$HOME/.config/composer/vendor/bin:$PATH" ;;
esac

# Directory jumping
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# Fuzzy finder bindings: Ctrl-T (files), Alt-C (cd). Ctrl-R is overridden by atuin below.
if command -v fzf >/dev/null 2>&1; then
  if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
  elif fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  fi
  [ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
fi

# History search. Load after fzf so atuin wins Ctrl-R, and before starship so atuin's
# preexec/precmd hooks attach before starship's.
if command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init zsh)"
fi

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v hx >/dev/null 2>&1; then
  export SUDO_EDITOR="hx"
  export EDITOR="hx"
fi

# Point Claude Code config at the workspace when running inside a devcontainer.
if [ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -d /workspaces ]; then
  _ws_dir="$(ls -1d /workspaces/*/ 2>/dev/null | head -n1)"
  if [ -n "$_ws_dir" ]; then
    export CLAUDE_CONFIG_DIR="${_ws_dir}.claude"
  fi
  unset _ws_dir
fi

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

if command -v ug >/dev/null 2>&1; then
  alias xzgrep='ug -z'
  alias xzegrep='ug -zE'
  alias xzfgrep='ug -zF'
fi

# Syntax highlighting (must be last)
if [ -f "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

if [[ -o interactive && -t 0 && -t 1 && $TERM != dumb ]]; then
  # Autosuggestions
  if [ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
    source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
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
fi

# Directory jumping is useful in both terminal and non-terminal interactive shells.
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

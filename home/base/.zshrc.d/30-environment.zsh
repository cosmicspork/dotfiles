if command -v hx >/dev/null 2>&1; then
  export SUDO_EDITOR="hx"
  export EDITOR="hx"
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER="delta"
fi

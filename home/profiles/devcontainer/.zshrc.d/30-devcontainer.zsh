# Point Claude Code config at the workspace when running inside a devcontainer.
if [ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -d /workspaces ]; then
  _ws_dirs=(/workspaces/*/)
  if [ -n "${_ws_dirs[1]:-}" ]; then
    export CLAUDE_CONFIG_DIR="${_ws_dirs[1]}.claude"
  fi
  unset _ws_dirs
fi

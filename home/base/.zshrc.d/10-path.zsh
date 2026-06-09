for _path_dir in \
  "$HOME/.local/bin" \
  "$HOME/.npm-global/bin" \
  "$HOME/.bun/bin" \
  "$HOME/.config/composer/vendor/bin" \
  "$HOME/.composer/vendor/bin"
do
  case ":$PATH:" in
    *":$_path_dir:"*) ;;
    *) export PATH="$_path_dir:$PATH" ;;
  esac
done
unset _path_dir

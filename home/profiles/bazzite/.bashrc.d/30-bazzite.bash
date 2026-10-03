# Bazzite-specific bash customizations live here.
#
# Reached only when zsh is unavailable: base .bashrc execs zsh for interactive
# sessions, and the zsh path sets this in .zshrc.d/30-bazzite.zsh. Kept in sync
# with that file and with Environment=LLAMA_CACHE in llama-server.service --
# a mismatch sends `llama-server -hf` downloads to ~/.cache/huggingface/hub,
# where the router never looks.
export LLAMA_CACHE="$HOME/.cache/llama.cpp"

# Kept in sync with the same block in .zshrc.d/30-bazzite.zsh: rustup is
# keg-only, so cargo and rustc are only reachable through the keg bin.
if [ -d /home/linuxbrew/.linuxbrew/opt/rustup/bin ]; then
  case ":$PATH:" in
    *":/home/linuxbrew/.linuxbrew/opt/rustup/bin:"*) ;;
    *) export PATH="/home/linuxbrew/.linuxbrew/opt/rustup/bin:$PATH" ;;
  esac
fi

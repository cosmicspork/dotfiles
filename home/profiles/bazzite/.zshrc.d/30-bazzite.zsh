# Bazzite-specific shell customizations live here.

# Must match Environment=LLAMA_CACHE in llama-server.service. Without it an
# interactive `llama-server -hf` falls back to ~/.cache/huggingface/hub, and the
# router -- which only reads this path -- never sees the model that was pulled.
export LLAMA_CACHE="$HOME/.cache/llama.cpp"

# rustup is keg-only, so its cargo/rustc proxies are not symlinked into the brew
# prefix; put the keg bin on PATH directly, as 30-macos.zsh does. Without it the
# host has rustup but no cargo, and every Rust repo falls back to a container.
if [ -d /home/linuxbrew/.linuxbrew/opt/rustup/bin ]; then
  case ":$PATH:" in
    *":/home/linuxbrew/.linuxbrew/opt/rustup/bin:"*) ;;
    *) export PATH="/home/linuxbrew/.linuxbrew/opt/rustup/bin:$PATH" ;;
  esac
fi

# Bazzite-specific shell customizations live here.

# Must match Environment=LLAMA_CACHE in llama-server.service. Without it an
# interactive `llama-server -hf` falls back to ~/.cache/huggingface/hub, and the
# router -- which only reads this path -- never sees the model that was pulled.
export LLAMA_CACHE="$HOME/.cache/llama.cpp"

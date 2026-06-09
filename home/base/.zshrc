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

for _dotfile in "$HOME"/.zshrc.d/*.zsh; do
  [ -f "$_dotfile" ] && source "$_dotfile"
done
unset _dotfile

if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi

# Syntax highlighting (must be last)
if [ -f "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

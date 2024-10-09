#!/bin/bash
sudo apt update
sudo apt install zsh nano
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
echo "set ZSH_THEME=\"powerlevel10k/powerlevel10k\" and plugins=(git git-prompt git-lfs github gitignore gnu-utils zsh-autosuggestions history-substring-search zsh-history-substring-search zsh-completions docker docker-compose copypath copyfile colored-man-pages colorize man screen systemd themes ufw zsh-interactive-cd zsh-syntax-highlighting)"
echo "read the script comments"
#Add it to FPATH in your .zshrc by adding the following line before source "$ZSH/oh-my-zsh.sh":
#fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

echo "Press any key to proceed..."

# Loop until a key is pressed
while true; do
read -rsn1 key  # Read a single character silently
if [[ -n "$key" ]]; then
nano .zshrc
exit 0

#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "Supply username and livepatch token"
    exit 1
fi

#upgrade os
apt update && apt dist-upgrade -y

#basic packages
#apt autoremove --purge snapd
apt install -y fonts-powerline \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    fish \
    cifs-utils \
    nfs-common \
    net-tools \
    iperf \
    git \
    build-essential	\
    curl \
    gnupg \
    lsb-release \
    unattended-upgrades

#livepatch
snap install canonical-livepatch
ua attach $2
ua enable livepatch

#unattended-upgrades
nano /etc/apt/apt.conf.d/50unattended-upgrades

#swappiness
swapoff -a
rm /swap.img
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
sysctl vm.swappiness=10
echo "vm.swappiness=10" >> /etc/sysctl.conf

#ufw
ufw allow openssh
ufw enable

# Add specified user
adduser $1

#docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
usermod -aG docker $1

#fish
chsh -s `which fish`
sudo -u $1 chsh -s `which fish`
fish -c "curl -L https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish"
fish -c "omf install bobthefish" 
sudo -u $1 fish -c "curl -L https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish"
sudo -u $1 fish -c "omf install bobthefish"
sudo chown -R $1:$1 /home/$1/.config/

exit 0

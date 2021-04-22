#!/bin/bash
#upgrade os
apt update && apt dist-upgrade

#basic packages
apt autoremove --purge snapd
apt install fonts-powerline \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    fish	

#swappiness
swapoff -a
rm /swap.img
fallocate -l 6G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
sysctl vm.swappiness=10
echo "vm.swappiness=10" >> /etc/sysctl.conf

exit 0

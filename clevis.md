clevis luks unlock -d /dev/sda3

https://kowalski7cc.xyz/blog/luks2-tpm2-clevis-fedora31

clevis luks bind -d /dev/sdX tpm2 '{ "pcr_bank":"sha256", "pcr_ids": "7,11" }

FIX for multidisk clevis! https://github.com/latchset/clevis/issues/272#issuecomment-770984147

sudo nano /usr/share/initramfs-tools/scripts/local-top/clevis
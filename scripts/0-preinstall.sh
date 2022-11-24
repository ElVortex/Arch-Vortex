#!/usr/bin/env bash
#github-action genshdoc
#
# @file Preinstall
# @brief Contains the steps necessary to configure and pacstrap the install to selected drive.

echo -ne "
-------------------------------------------------------------------------
  ██╗  ██╗ ██████╗ ██████╗ ████████╗██████╗██╗  ██╗     ██████╗ ███████╗
  ██║  ██║██╔═══██╗██╔══██╗╚══██╔══╝██╔═══ ╚██╗██╔╝    ██╔═══██╗██╔════╝
  ██║  ██║██║   ██║██████╔╝   ██║   ████╗   ╚███╔╝ ███╗██║   ██║███████╗
  ╚██╗██╔╝██║   ██║██╔══██╗   ██║   ██╔═╝   ██╔██╗ ╚══╝██║   ██║╚════██║
   ╚███╔╝ ╚██████╔╝██║  ██║   ██║   ██████╗██╔╝╚██╗    ╚██████╔╝███████║
    ╚══╝   ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═════╝╚═╝  ╚═╝     ╚═════╝ ╚══════╝
                            original:github.com/ChrisTitusTech/ArchTitus
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
-------------------------------------------------------------------------
Setting up mirrors for optimal download
"

source $CONFIGS_DIR/setup.conf
timedatectl set-ntp true
pacman -S --noconfirm archlinux-keyring
pacman -S --noconfirm --needed pacman-contrib terminus-font
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf
pacman -S --noconfirm --needed reflector rsync grub
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
reflector -a 48 -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
mkdir /mnt &>/dev/null



echo -ne "
-------------------------------------------------------------------------
                    Installing Prerequisites
-------------------------------------------------------------------------
"

pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc



echo -ne "
-------------------------------------------------------------------------
                    Formating Disk
-------------------------------------------------------------------------
"

umount -A --recursive /mnt
sgdisk -Z ${DISK}
sgdisk -a 2048 -o ${DISK}
sgdisk -n 1::+1M --typecode=1:ef02 ${DISK}
sgdisk -n 2::+300M --typecode=2:ef00 --change-name=2:'EFIBOOT' ${DISK}
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${DISK}
if [[ ! -d "/sys/firmware/efi" ]]; then
    sgdisk -A 1:set:2 ${DISK}
fi
partprobe ${DISK}



echo -ne "
-------------------------------------------------------------------------
                    Creating Filesystems
-------------------------------------------------------------------------
"

createsubvolumes () {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
}

mountallsubvol () {
    if [[ "${FS}" == "btrfs" ]]; then
        mount -o ${MOUNT_OPTIONS},subvol=@home ${partition3} /mnt/home
    else
        mount -o ${MOUNT_OPTIONS},subvol=@home /dev/mapper/cryptroot /mnt/home
    fi
}

subvolumesetup () {
    cd /mnt
    createsubvolumes
    cd /
    umount /mnt
    if [[ "${FS}" == "btrfs" ]]; then
        mount -o ${MOUNT_OPTIONS},subvol=@ ${partition3} /mnt
    else
        mount -o ${MOUNT_OPTIONS},subvol=@ /dev/mapper/cryptroot /mnt
    fi
    mkdir -p /mnt/{home,boot}
    mountallsubvol
}


if [[ "${DISK}" =~ "nvme" ]]; then
    partition2=${DISK}p2
    partition3=${DISK}p3
else
    partition2=${DISK}2
    partition3=${DISK}3
fi


if [[ "${FS}" == "btrfs" ]]; then
    mkfs.fat -F32 ${partition2}
    mkfs.btrfs ${partition3} -f
    mount ${partition3} /mnt
    subvolumesetup
elif [[ "${FS}" == "ext4" ]]; then
    mkfs.vfat -F32 ${partition2}
    mkfs.ext4 ${partition3}
    mount ${partition3} /mnt
elif [[ "$FS" == "luks-btrfs" ]]; then
    mkfs.vfat -F32 ${partition2}
    echo -n "${LUKS_PASSWORD}" | cryptsetup -y -v --cipher aes-xts-plain64 --hash sha512 --use-random luksFormat ${partition3}
    echo -n "${LUKS_PASSWORD}" | cryptsetup open ${partition3} cryptroot
    mkfs.btrfs /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    subvolumesetup
    echo ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value ${partition3}) >> $CONFIGS_DIR/setup.conf
elif [[ "$FS" == "luks-ext4" ]]; then
    mkfs.vfat -F32 ${partition2}
    echo -n "${LUKS_PASSWORD}" | cryptsetup -y -v --cipher aes-xts-plain64 --hash sha512 --use-random luksFormat ${partition3}
    echo -n "${LUKS_PASSWORD}" | cryptsetup open ${partition3} cryptroot
    mkfs.ext4 /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    echo ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value ${partition3}) >> $CONFIGS_DIR/setup.conf
fi


mkdir -p /mnt/boot/EFI
mount ${partition2} /mnt/boot/


if ! grep -qs '/mnt' /proc/mounts; then
    echo "Drive is not mounted can not continue"
    echo "Rebooting in 3 Seconds ..." && sleep 1
    echo "Rebooting in 2 Seconds ..." && sleep 1
    echo "Rebooting in 1 Second ..." && sleep 1
    reboot now
fi



echo -ne "
-------------------------------------------------------------------------
                    Arch Install on Main Drive
-------------------------------------------------------------------------
"

pacstrap /mnt base base-devel linux linux-firmware vim nano sudo archlinux-keyring wget libnewt --noconfirm --needed
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
cp -R ${SCRIPT_DIR} /mnt/root/Arch-Vortex
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

genfstab -U /mnt >> /mnt/etc/fstab
echo "
  Generated /etc/fstab:
"
cat /mnt/etc/fstab



echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"

if [[ ! -d "/sys/firmware/efi" ]]; then
    grub-install --boot-directory=/mnt/boot ${DISK}
else
    pacstrap /mnt efibootmgr --noconfirm --needed
fi



echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 1-setup.sh
-------------------------------------------------------------------------
"

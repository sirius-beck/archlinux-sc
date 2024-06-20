#!/usr/bin/env bash

export username="arch"
export password="123456"
export root_password="123456"

export keymap="br-abnt2"
export timezone="America/Sao_Paulo"
export locale="en_US.UTF-8"
export hostname="ArchLinuxSC"

export disk_setup_method="scheme" # scheme || layout
export partition_scheme=(
	"efi /dev/sda1"
	"root /dev/sda2"
	"swap /dev/sda3"
) # template: label partition
export partition_layout=(
	"efi 1MiB 301MiB"
	"swap 301MiB 2.3GiB"
	"root 2.3GiB 100%"
) # template: label start end
export device="/dev/sda"
export partition_table="gpt" # gpt || msdos
export filesystem="ext4"

export kernel="linux-zen"
export boot_manager="systemd-boot" # grub (UEFI x64) || systemd-boot (UEFI x86 e x64) || syslinux (BIOS)
export enable_dual_boot=false      # true || false; only GRUB

export aur_helper="paru"         # paru || yay
export enable_cachyos_repo=false # true || false

export gpu_driver="nvidia"       # nvidia || amd || intel
export xorg_mode="server"        # server || minimal || full
export desktop_environment="kde" # kde || gnome || xfce || i3

# default settings (do not change)
export system_bits="$(cat /sys/firmware/efi/fw_platform_size)"
export log_file="archzen/archzen.log"
export efi_partition efi_mountpoint

if ! [[ -d /sys/firmware/efi ]]; then
	partition_table="msdos"
	layout=(
		"swap 1MiB 8GiB"
		"boot 8GiB 100%"
	)
fi

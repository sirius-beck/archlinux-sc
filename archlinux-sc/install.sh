#!/usr/bin/env bash

source ./config.sh
source ./utils.sh

function keyring_init() {
	pacman-key --init
	pacman-key --populate
}

function setup_keyboard() {
	local found_keymap=$(localectl list-keymaps | grep -o $keymap)

	if [[ ! $found_keymap ]]; then
		echo "$keymap is not a valid keyboard layout."
		return 1
	fi

	loadkeys "$keymap"
}

function setup_network() {
	local iw_ssid, iw_password
	local iw_interface=$(iwctl device list | grep wl | awk '{print $2; exit}')

	if [[ "$iw_interface" ]]; then
		iwctl station "$iw_interface" scan
		sleep 5
		iwctl station "$iw_interface" get-networks

		read -rp "Enter the network name: " iw_ssid
		read -rp "Enter the network password: " iw_password

		iwctl --passphrase "$iw_password" station "$iw_interface" connect "$iw_ssid"
		sleep 10
	fi

	if ! ping archlinux.org -c 1; then
		echo "You are not connected to the internet."
		return 1
	fi
}

function setup_timezone() {
	local found_timezone=$(timedatectl list-timezones | grep "$timezone")

	if [[ ! $found_timezone ]]; then
		echo "$timezone is not a valid timezone."
		return 1
	fi

	timedatectl set-timezone "$timezone"
	timedatectl set-ntp true
}

function setup_disk() {
	function setup_scheme() {
		echo "Setup disk from an existing partition scheme"

		for scheme in "${partition_scheme[@]}"; do
			local scheme=($scheme)
			local label=${scheme[0]}
			local partition=${scheme[1]}
			local mountpoint="/mnt/$label"

			case $label in
			"efi")
				mkfs.fat -F32 "$partition"
				efi_partition="$partition"
				efi_mountpoint="/boot/efi"
				;;
			"boot")
				mkfs."$filesystem" "$partition"
				mount "$partition" "/mnt"
				efi_partition="$partition"
				efi_mountpoint="/"
				;;
			"swap")
				mkswap "$partition"
				swapon "$partition"
				;;
			*)
				mountpoint=$(echo "$mountpoint" | sed 's/\/root//')
				mkfs."$filesystem" "$partition"
				mount "$partition" "$mountpoint"
				;;
			esac
		done
	}

	function setup_layout() {
		echo "Setup disk from a new partition scheme"
		parted -s -a optimal "$device" mktable "$partition_table"

		index=1
		for layout in "${partition_layout[@]}"; do
			local layout=($layout)
			local label=${layout[0]}
			local starting_block=${layout[1]}
			local final_block=${layout[2]}
			local type=$(is_uefi && echo "$label" || echo "-t primary")
			local partition="${device}$index"
			local mountpoint="/mnt/$label"

			case $label in
			"efi")
				parted -s -a optimal "$device" mkpart "$type" fat32 "$starting_block" "$final_block"
				parted -s -a optimal "$device" set $index esp on
				mkfs.fat -F32 "$partition"
				efi_partition="$partition"
				efi_mountpoint="/boot/efi"
				;;
			"boot")
				parted -s -a optimal "$device" mkpart "$type" "$filesystem" "$starting_block" "$final_block"
				parted -s -a optimal "$device" set $index boot on
				mkfs."$filesystem" "$partition"
				mount "$partition" "/mnt"
				efi_partition="$partition"
				efi_mountpoint="/"
				;;
			"swap")
				parted -s -a optimal "$device" mkpart "$type" linux-swap "$starting_block" "$final_block"
				mkswap "$partition"
				swapon "$partition"
				;;
			*)
				mountpoint=$(echo "$mountpoint" | sed 's/\/root//')
				parted -s -a optimal "$device" mkpart "$type" "$filesystem" "$starting_block" "$final_block"
				mkfs."$filesystem" "$partition"
				mountpoint=$(echo "$mountpoint" | sed 's/\/root//')
				mount "$partition" "$mountpoint"
				;;
			esac

			((index++))
		done
	}

	eval "setup_${disk_setup_method}"
}

function setup_mirrors() {
	mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
	reflector --latest 5 --sort rate --download-timeout 30 --save /etc/pacman.d/mirrorlist
}

function setup_pacman() {
	local pacman_conf="/etc/pacman.conf"

	# enable color and parallel downloads
	sed -i "/# Misc options/a ILoveCandy" $pacman_conf
	sed -i "s/#Color/Color/" $pacman_conf
	sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 20/" $pacman_conf

	# enable multilib repository
	local line=$(grep -n "\[multilib\]" $pacman_conf | cut -d: -f1)
	sed -i "${line}s/#//" $pacman_conf
	sed -i "$((line + 1))s/#//" $pacman_conf
	pacman -Syy --noconfirm
}

function install_basesystem() {
	local packages=(
		"base"
		"base-devel"
		"linux-firmware"
		"sudo"
		"networkmanager"
		"vim"
		"git"
		"wget"
	)

	pacstrap -P /mnt "${packages[@]}"
}

function gen_fstab() {
	genfstab -U /mnt >>/mnt/etc/fstab
}

function setup_users() {
	arch-chroot /mnt useradd -m -G wheel,storage "$username"

	chpasswd --root /mnt <<<"root:$root_password"
	chpasswd --root /mnt <<<"$username:$password"

	sed -i "s/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/" /mnt/etc/sudoers
}

start_post_installation_steps() {
	[[ -d /mnt/archzen ]] && rm -rf /mnt/archzen
	mkdir /mnt/archzen

	cp ./config.sh /mnt/archzen/config.sh
	cp ./utils.sh /mnt/archzen/utils.sh
	cp ./post-install.sh /mnt/archzen/post-install.sh

	arch-chroot /mnt /usr/bin/bash -c "\
		chmod +x /archzen/post-install.sh && \
		cd /archzen && \
		./post-install.sh $efi_partition $efi_mountpoint"
}

function run_all_tasks() {

	run_task "Updating package database" keyring_init || return 1
	run_task "Setting up keyboard layout" setup_keyboard || return 1
	run_task "Setting up network" setup_network || return 1
	run_task "Setting up timezone" setup_timezone || return 1
	run_task "Creating and formatting partitions" setup_disk || return 1
	run_task "Updating mirrors" setup_mirrors || return 1
	run_task "Setting up pacman" setup_pacman || return 1
	run_task "Installing base system" install_basesystem || return 1
	run_task "Generating fstab" gen_fstab || return 1
	run_task "Setting up user and root" setup_users || return 1

	start_post_installation_steps || return 1
}

main() {
	if run_all_tasks; then
		umount -R /mnt &>/dev/null
		printf "\nArchZen has finished the installation process. Please reboot the system!"
		yesno "Do you want to reboot now?" && reboot
	else
		echo "An error occurred."
		echo -e "Check the log file for more information: $(color cyan "$log_file")"
		cat "/mnt/${log_file}" 1>>"/${log_file}" 2>/dev/null
		umount -R /mnt &>/dev/null
		exit 1
	fi
}

setfont ter-122b
load_header "Starting Archlinux installation..."
yesno "Do you want to start the installation now?" && main

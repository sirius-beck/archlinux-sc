#!/usr/bin/env bash

source ./config.sh
source ./utils.sh

efi_partition="$1"
efi_mountpoint="$2"

function setup_timezone() {
	ln -sf /usr/share/zoneinfo/"${timezone}" /etc/localtime
	hwclock --systohc
}

function setup_location() {
	sed -i "s/#$locale/$locale/" /etc/locale.gen
	locale-gen
	echo "LANG=${locale}" >>/etc/locale.conf
	echo "KEYMAP=${keymap}" >>/etc/vconsole.conf
}

function setup_network() {
	echo "$hostname" >/etc/hostname

	hosts=(
		"127.0.0.1    localhost"
		"::1          localhost"
		"127.0.0.1    ${hostname}.localdomain    $hostname"
	)

	for host in "${hosts[@]}"; do
		echo "$host" >>/etc/hosts
	done

	systemctl enable NetworkManager.service
}

function install_cachyos_repo() {

	function run_first_setup() {
		local mirror_cachyos="https://mirror.cachyos.org/repo/x86_64/cachyos"

		pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
		pacman-key --lsign-key F3B607488DB35A47

		pacman -U --noconfirm "${mirror_cachyos}/cachyos-keyring-20240331-1-any.pkg.tar.zst" \
			"${mirror_cachyos}/cachyos-mirrorlist-18-1-any.pkg.tar.zst" \
			"${mirror_cachyos}/cachyos-v3-mirrorlist-18-1-any.pkg.tar.zst" \
			"${mirror_cachyos}/cachyos-v4-mirrorlist-6-1-any.pkg.tar.zst" \
			"${mirror_cachyos}/pacman-6.1.0-5-x86_64.pkg.tar.zst"
	}

	function add_repo_from_version() {
		local version="$1"

		if [[ $version != "v2" ]]; then
			add_repo "official" "cachyos-${version}" "/etc/pacman.d/cachyos-${version}-mirrorlist"
			add_repo "official" "cachyos-core-${version}" "/etc/pacman.d/cachyos-${version}-mirrorlist"
			add_repo "official" "cachyos-extra-${version}" "/etc/pacman.d/cachyos-${version}-mirrorlist"
		fi

		add_repo "official" "cachyos" "/etc/pacman.d/cachyos-mirrorlist"
	}

	add_cachyos_repo() {
		local repo_v4=$(/lib/ld-linux-x86-64.so.2 --help | grep supported | grep v4)
		local repo_v3=$(/lib/ld-linux-x86-64.so.2 --help | grep supported | grep v3)
		local repo_v2=$(/lib/ld-linux-x86-64.so.2 --help | grep supported | grep v2)

		if [[ $repo_v4 ]]; then
			add_repo_from_version "v4" && return 0
			return 1
		elif [[ $repo_v3 ]]; then
			add_repo_from_version "v3" && return 0
			return 1
		elif [[ $repo_v2 ]]; then
			add_repo_from_version "v2" && return 0
			return 1
		fi
	}

	run_first_setup || return 1
	add_cachyos_repo || return 1

	pacman -Syyu --noconfirm
}

function install_kernel() {
	if is_aur_package "$kernel"; then
		install_from_aur "$kernel" "${kernel}-headers"
	else
		install_from_repo "$kernel" "${kernel}-headers"
	fi
}

function install_microcode() {
	cpu_vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')
	amdcpu=$(echo "$cpu_vendor" | grep -iq "amd")
	intelcpu=$(echo "$cpu_vendor" | grep -iq "intel")

	if [[ $amdcpu ]]; then
		install_from_repo amd-ucode
	elif [[ $intelcpu ]]; then
		install_from_repo intel-ucode
	fi
}

function install_boot_manager() {
	if is_uefi; then
		if [ "$system_bits" = "32" ]; then
			boot_manager="systemd-boot"
		fi
	else
		boot_manager="syslinux"
	fi

	boot_manager=${boot_manager//"-"/"_"} # replace hyphen with underscore

	function install_grub() {
		install_from_repo grub efibootmgr
		grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory="$efi_mountpoint" --recheck

		if [ "$enable_dual_boot" = true ]; then
			install_from_repo os-prober
			echo "GRUB_DISABLE_OS_PROBER=false" >>/etc/default/grub
		fi

		grub-mkconfig -o /boot/grub/grub.cfg
	}

	function install_systemd_boot() {
		bootctl --path="$efi_mountpoint" install
		bootctl --path="$efi_mountpoint" update
		systemctl enable systemd-boot-update.service
	}

	function install_syslinux() {
		install_from_repo syslinux gptfdisk mtools
		syslinux-install_update -i -a -m
	}

	if is_uefi; then
		mkdir -p "$efi_mountpoint"
		mount "$efi_partition" "$efi_mountpoint"
	fi

	eval "install_${boot_manager}"
}

function install_gpu_drivers() {
	local nvidia

	case $kernel in
	"linux")
		nvidia="nvidia"
		;;
	"linux-lts")
		nvidia="nvidia-lts"
		;;
	"linux-zen")
		nvidia="nvidia-zen"
		;;
	"linux-hardened")
		nvidia="nvidia-hardened"
		;;
	*)
		nvidia="${kernel}-nvidia"
		;;
	esac

	function install_xorg_server() {
		install_from_repo xorg-server xorg-xinit
	}

	function install_xorg_minimal() {
		install_from_repo xorg-server xorg-xinit xorg-xclock xterm
	}

	function install_xorg_full() {
		install_from_repo xorg
	}

	function install_nvidia_driver() {
		install_from_repo "$nvidia" nvidia-settings nvidia-utils
	}
	function install_amd_driver() {
		install_from_repo xf86-video-amdgpu
	}
	function install_intel_driver() {
		install_from_repo xf86-video-intel
	}

	eval "install_xorg_${xorg_mode}"
	eval "install_${gpu_driver}_driver"
}

install_desktop_env() {
	function install_gnome() {
		install_from_repo gnome
		systemctl enable gdm.service
	}

	function install_kde() {
		install_from_repo plasma-meta plasma-wayland-session konsole dolphin kate ark sddm
		systemctl enable sddm.service
	}

	eval "install_${desktop_environment}"
}

function install_extra_packages() {
	libs_pkgs=(
		ffmpeg
		gstreamer
		gst-plugins-base
		gst-plugins-bad
		gst-plugins-good
		gst-plugins-ugly
	)

	file_systems_pkgs=(
		btrfs-progs
		dosfstools
		e2fsprogs
		exfatprogs
		f2fs-tools
		lvm2
		mtools
		ntfs-3g
		reiserfsprogs
		util-linux
		xfsprogs
	)

	terminal_pkgs=(
		lsd
		neofetch
		rsync
		less
		lesspipe
	)

	install_from_repo "${libs_pkgs[@]}"
	install_from_repo "${file_systems_pkgs[@]}"
	install_from_repo "${terminal_pkgs[@]}"
}

function run_all_tasks() {
	run_task "Setting up timezone" setup_timezone || exit 1
	run_task "Setting up location" setup_location || exit 1
	run_task "Setting up network" setup_network || exit 1
	if [ "$enable_cachyos_repo" = true ]; then
		run_task "Installing CachyOS repository" install_cachyos_repo || exit 1
	fi
	run_task "Installing kernel" install_kernel || exit 1
	run_task "Installing microcode" install_microcode || exit 1
	run_task "Installing boot manager" install_boot_manager || exit 1
	run_task "Installing GPU drivers" install_gpu_drivers || exit 1
	run_task "Installing desktop environment" install_desktop_env || exit 1
	run_task "Installing extra packages" install_extra_packages || exit 1
}

load_header "Starting post installation script..."
yesno "Do you want to start the post installation script?" && run_all_tasks

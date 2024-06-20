function yesno() {
	while true; do
		read -r -p "$* [y/n]: " yn
		case $yn in
		[Yy]*)
			echo
			return 0
			;;
		[Nn]*)
			echo
			return 1
			;;
		esac
	done
}

function color() {

	function red {
		local text="$*"
		echo -e "\033[1;31m$text\033[0m"
	}

	function green {
		local text="$*"
		echo -e "\033[1;32m$text\033[0m"
	}

	function yellow {
		local text="$*"
		echo -e "\033[1;33m$text\033[0m"
	}

	function blue {
		local text="$*"
		echo -e "\033[1;34m$text\033[0m"
	}

	function purple {
		local text="$*"
		echo -e "\033[1;35m$text\033[0m"
	}

	function cyan {
		local text="$*"
		echo -e "\033[1;36m$text\033[0m"
	}

	"$@"
}

function banner() {
	color purple "#################################"
	color purple "#            ArchZen            #"
	color purple "#################################"
}

function load_header() {
	local message="$1"

	clear
	banner

	echo
	echo "$message"
	echo
}

function run_task() {
	local task_text="$1"
	local task_func="$2"

	echo -n "[  ] $task_text..."
	if eval "$task_func" &>/$log_file; then
		echo -e "\r$(color green "[OK]") $task_text... $(color green "Done")!"
		return 0
	else
		echo -e "\r$(color red "[!!]") $task_text... $(color red "Failed")!"
		return 1
	fi
}

function is_uefi() {
	[ -d /sys/firmware/efi ] && return 0 || return 1
}

function is_aur_package() {
	local package="$1"
	local found_items=$(pacman -Ssq "$package" | grep "$package")

	for item in "${found_items[@]}"; do
		if [[ $item == "$package" ]]; then
			return 1
		fi
	done

	return 0
}

function install_from_repo() {
	local packages=($@)

	for package in "${packages[@]}"; do
		pacman -S --noconfirm --needed "$package"
	done
}

function install_from_aur() {
	local packages=($@)

	for package in "${packages[@]}"; do
		local url="https://aur.archlinux.org/${package}.git"
		local out_dir="/tmp/${package}"

		git clone "$url" "$out_dir"
		cd "$out_dir" && makepkg -sirc --noconfirm
		cd ~ && rm -rf "$out_dir"
	done
}

function add_repo() {
	local type="$1" # official | custom
	local repo_name="$2"
	local repo_url="$3"

	if [[ $type == "official" ]]; then
		local line=$(grep -n "\[core-testing\]" /etc/pacman.conf | cut -d: -f1)

		line=$((line - 1))
		sed -i "${line}i\[$repo_name\]" /etc/pacman.conf
		sed -i "$((line + 1))iInclude = $repo_url\\n" /etc/pacman.conf
	elif [[ $type == "custom" ]]; then
		local sig_level="$4" # optional

		echo -e "\n[$repo_name]" >>/etc/pacman.conf
		echo "SigLevel = $sig_level" >>/etc/pacman.conf
		echo "Server = $repo_url" >>/etc/pacman.conf
	else
		echo "Invalid repository type"
		return 1
	fi

}

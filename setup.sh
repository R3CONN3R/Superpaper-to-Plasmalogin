#!/usr/bin/env bash
set -euo pipefail

RESET="\033[0m"
BOLD="\033[1m"
BLUE="\033[34m"
GREEN="\033[92m"
RED="\033[91m"
YELLOW="\033[93m"
CHECK="${GREEN}✔️${RESET}"
PENDING="${GREEN}…${RESET}"

SCRIPT_VERSION="1.0"

SERVICE_NAME="superpaper-to-plasmalogin-sync"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PATH_FILE="/etc/systemd/system/${SERVICE_NAME}.path"
SYNC_SCRIPT_FOLDER="/var/opt/${SERVICE_NAME}"
SYNC_SCRIPT="${SYNC_SCRIPT_FOLDER}/${SERVICE_NAME}"

DEST="/var/lib/plasmalogin/wallpapers"
OWNER="plasmalogin:plasmalogin"

PLASMOID_NAME="superpaper.to.plasmalogin"
PLASMOID_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/${PLASMOID_NAME}"
PLASMOID_DEST="/usr/share/plasma/wallpapers/${PLASMOID_NAME}"

CONFIG_FILE="/etc/plasmalogin.conf.d/90-${SERVICE_NAME}.conf"
DEBOUNCE_SECONDS=3

INSTALL_USER=""

print_banner() {
	clear
	echo -e "${BLUE}==========================================${RESET}"
	echo -e "${BLUE}   ${SERVICE_NAME} v${SCRIPT_VERSION}     ${RESET}"
	echo -e "${BLUE}==========================================${RESET}"
	echo ""
}

print_result() {
	printf "${BOLD}%-25s : ${YELLOW}%s${RESET}\n" "$1" "$2"
}

error() {
	echo
	echo -e "${RED}Error:${RESET} $*" >&2
	exit 1
}

run_as_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		if ! command -v sudo >/dev/null 2>&1; then error "sudo is required."; fi
		if [[ -z "${INSTALL_USER:-}" ]]; then INSTALL_USER="$(id --user --name)"; fi
		exec sudo "$0" --root --install-user "$INSTALL_USER"
	fi
}

check_install_dependencies() {
	printf '%s' "Checking dependencies"

	if [[ -z "${INSTALL_USER:-}" ]]; then INSTALL_USER="${SUDO_USER:-${USER:-}}"; fi
	if [[ -z "$INSTALL_USER" || "$INSTALL_USER" == "root" ]]; then error "Run this script as the desktop user, for example: ./setup.sh"; fi
	if ! getent passwd "$INSTALL_USER" >/dev/null; then error "User '$INSTALL_USER' does not exist."; fi

	local user_home
	user_home="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"
	SUPERPAPER_SOURCE="${user_home}/.cache/superpaper/temp"

	if [[ ! -d "$SUPERPAPER_SOURCE" ]]; then error "Source directory does not exist:\n$SUPERPAPER_SOURCE"; fi
	if [[ ! -d "$DEST" ]]; then error "Destination directory does not exist:\n$DEST"; fi
	if ! getent passwd plasmalogin >/dev/null; then error "User 'plasmalogin' does not exist."; fi
	if ! getent group plasmalogin >/dev/null; then error "Group 'plasmalogin' does not exist."; fi
	if ! RSYNC_BIN="$(command -v rsync)"; then error "rsync is required but was not found."; fi
	if ! SLEEP_BIN="$(command -v sleep)"; then error "sleep was not found. How..."; fi
	if ! CHOWN_BIN="$(command -v chown)"; then error "chown was not found. How..."; fi
	if [[ ! -d "$PLASMOID_SRC" ]]; then error "Plasmoid source directory does not exist:\n$PLASMOID_SRC"; fi

	printf '\033[50G%b\n' "$CHECK"
}

install_plasmoid() {
	printf '%s' "Installing wallpaper plasmoid"

	cp -a "$PLASMOID_SRC" "$(dirname "$PLASMOID_DEST")/"
	chown -R root:root "$PLASMOID_DEST"
	chmod -R 755 "$PLASMOID_DEST"

	printf '\033[50G%b\n' "$CHECK"
}

configure_plasmalogin() {
	# Has to be manually configured.
	# See: https://wiki.archlinux.org/title/Plasma_Login_Manager#Custom_wallpaper_plugins
	printf '%s' "Installing plasmalogin.conf override"
	printf '\033[50G%b\n' "$PENDING"
	printf '%s' "$(basename -- $CONFIG_FILE)"
	printf '\033[50G%b\n' "$CHECK"

	cat >"$CONFIG_FILE" <<EOF
[Greeter]
WallpaperPluginId=${PLASMOID_NAME}
EOF
}

install_sync_service() {
	printf '%s' "Installing synchronization service"

	# Safely quote paths for the generated synchronization script.
	SOURCE_QUOTED="$(printf '%q' "$SUPERPAPER_SOURCE")"
	DEST_QUOTED="$(printf '%q' "$DEST")"
	RSYNC_QUOTED="$(printf '%q' "$RSYNC_BIN")"
	CHOWN_QUOTED="$(printf '%q' "$CHOWN_BIN")"
	SLEEP_QUOTED="$(printf '%q' "$SLEEP_BIN")"

	install -d -m 0755 "$SYNC_SCRIPT_FOLDER"

	cat >"$SYNC_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SOURCE=${SOURCE_QUOTED}
DEST=${DEST_QUOTED}

# Wait for Superpaper to process all images.
${SLEEP_QUOTED} ${DEBOUNCE_SECONDS}

# Mirror the source contents into the destination.
# --delete removes files and directories no longer present in the source.
# --include only png --exlude everything else
${RSYNC_QUOTED} -a --delete --include "*.png" --exclude "*" -- "\$SOURCE/" "\$DEST/"

# Set the requested ownership on the destination and its contents.
${CHOWN_QUOTED} -R ${OWNER} -- "\$DEST"
EOF

	chmod 0755 "$SYNC_SCRIPT"

	cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Synchronize Superpaper wallpapers to Plasmalogin

[Service]
Type=oneshot
User=root
Group=root
ExecStart=${SYNC_SCRIPT}
EOF

	cat >"$PATH_FILE" <<EOF
[Unit]
Description=Watch Superpaper wallpaper directory

[Path]
PathChanged=${SUPERPAPER_SOURCE}
Unit=${SERVICE_NAME}.service

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
	systemctl enable --now "${SERVICE_NAME}.path" >/dev/null 2>&1

	# Perform an initial synchronization.
	systemctl start "${SERVICE_NAME}.service" >/dev/null 2>&1

	printf '\033[50G%b\n' "$CHECK"
}

install_sync() {
	check_install_dependencies
	install_plasmoid
	configure_plasmalogin
	install_sync_service
	echo
	printf '%b\033[50G%b\n' "${GREEN}Installation complete${RESET}" "$CHECK"
	echo
	echo -e "${BOLD}Installation configuration:${RESET}"
	echo
	print_result "Watching" "$SUPERPAPER_SOURCE"
	print_result "Synchronizing to" "$DEST"
	print_result "Destination ownership" "$OWNER"

	echo
	status
}

uninstall_sync() {
	echo -e "${YELLOW}Uninstalling ${SERVICE_NAME}${RESET}"
	echo

	if [[ -f "$SERVICE_FILE" ]]; then
		systemctl disable --now "${SERVICE_NAME}.path" 2>/dev/null || true
		systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
		echo "Removing ${SERVICE_FILE}"
		rm -f -- "$SERVICE_FILE"
	else
		printf '%s\n' "$SERVICE_FILE not found."
	fi

	if [[ -f "$PATH_FILE" ]]; then
		systemctl disable --now "${SERVICE_NAME}.path" 2>/dev/null || true
		echo "Removing ${PATH_FILE}"
		rm -f -- "$PATH_FILE"
	else
		printf '%s\n' "$PATH_FILE not found."
	fi

	if [[ -f "$SYNC_SCRIPT" ]]; then
		rm -f -- "$SYNC_SCRIPT"
		rmdir -- "$SYNC_SCRIPT_FOLDER"
	else
		printf '%s\n' "$SYNC_SCRIPT not found."
	fi

	systemctl daemon-reload
	systemctl reset-failed "${SERVICE_NAME}.service" \
		"${SERVICE_NAME}.path" 2>/dev/null || true

	if [[ -d "$PLASMOID_DEST" ]]; then
		echo "Removing $PLASMOID_DEST"
		# Yes. rm -rf is tested.
		# Hardcoded path from variable and -d check
		# Proper escaping
		# -- to tell everything after this is a positional argument not an option
		rm -rf -- "$PLASMOID_DEST"
	fi

	if [[ -e "$CONFIG_FILE" ]]; then
		printf '%s\n' "Removing $CONFIG_FILE"
		rm -f -- "$CONFIG_FILE"
	else
		printf '%s\n' "$CONFIG_FILE  not found"
	fi

	echo
	echo -e "${GREEN}Uninstallation complete.${RESET}"
}

status() {
	echo -e "${BOLD}Installation status:${RESET}"
	echo

	if [[ -d "$PLASMOID_DEST" ]]; then
		print_result "Wallpaper plasmoid" "installed"
	else
		print_result "Wallpaper plasmoid" "not installed"
	fi

	if [[ -f "$CONFIG_FILE" ]] && grep -q "^WallpaperPluginId=${PLASMOID_NAME}$" "$CONFIG_FILE"; then
		print_result "Plasmalogin config" "configured"
	else
		print_result "Plasmalogin config" "not configured"
	fi

	if [[ -f "$SERVICE_FILE" ]]; then
		print_result "Service unit" "installed"
	else
		print_result "Service unit" "not installed"
	fi

	if [[ -f "$PATH_FILE" ]]; then
		print_result "Path unit" "installed and $(systemctl is-active "${SERVICE_NAME}.path")"
	else
		print_result "Path unit" "not installed"
	fi
}

show_menu() {
	while true; do
		print_banner
		echo -e "  1) ${GREEN}Install${RESET}"
		echo -e "  2) ${RED}Uninstall${RESET}"
		echo -e "  3) ${YELLOW}Check status${RESET}"
		echo -e "  4) ${BOLD}Exit${RESET}"
		echo

		read -r -p "Choose an option [1-4]: " choice
		echo

		case "$choice" in
		1)
			print_banner
			install_sync
			;;
		2)
			print_banner
			uninstall_sync
			;;
		3)
			print_banner
			status
			;;
		4)
			clear
			exit 0
			;;
		*)
			continue
			# echo -e "${RED}Invalid option.${RESET}"
			;;
		esac

		echo
		read -r -p "Press Enter to return to the menu…"
		clear
	done
}

# ACTION="${1:-menu}"
INSTALL_USER="${INSTALL_USER:-}"

# Re-run as root while preserving the desktop user.
if [[ "${EUID}" -ne 0 ]]; then
	run_as_root
fi

show_menu

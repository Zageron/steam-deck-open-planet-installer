#!/usr/bin/env bash
# DISCLAIMER: GitHub Copilot used GPT-5.6 Luna to generate this script.
# NOTE: ASD-STE100 keeps the script text short and clear.
# CAUTION: Examine this script before you use it. It changes game files.

set -euo pipefail
IFS=$'\n\t'

readonly APPID="2225070"
readonly DOWNLOAD_PAGE_URL="https://openplanet.dev/download/next"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

FORCE=0
STATUS_ONLY=0
STEAM_ROOT=""
TRACKMANIA_DIR=""
TMP_ROOT=""

info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }

warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }

die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage()
{
	cat <<EOF
Usage:
  $SCRIPT_NAME [--status] [--force]

Options:
  --status   Check the current installation.
	--force    Install Openplanet again.
  -h, --help Show this help.
EOF
}

for argument in "$@"; do
	case "$argument" in
		--status)
			STATUS_ONLY=1
			;;
		--force)
			FORCE=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "Unknown option: $argument"
			;;
	esac
done

require_command() { command -v "$1" >/dev/null 2>&1 || die "The command '$1' is required."; }

for command_name in find sed; do
	require_command "$command_name"
done

SEVENZIP=""
if [[ "$STATUS_ONLY" -eq 0 ]]; then
	for command_name in curl mktemp; do
		require_command "$command_name"
	done
	SEVENZIP="$(command -v 7z || command -v 7zz || true)"
	[[ -n "$SEVENZIP" ]] || die "7-Zip is required for installation."
fi

add_library()
{
	local library="$1"

	[[ -d "$library" ]] || return 0
	library="${library%/}"

	for existing in "${LIBRARIES[@]}"; do
		[[ "$existing" == "$library" ]] && return 0
	done

	LIBRARIES+=("$library")
}

read_vdf()
{
	sed -nE \
		"s/^[[:space:]]*\"$1\"[[:space:]]*\"([^\"]+)\".*$/\1/p" \
		"$2"
}

has_dll_override()
{
	local user_reg="$1"

	[[ -f "$user_reg" ]] &&
		[[ -n "$(sed -nE \
			'/^\[Software\\\\Wine\\\\DllOverrides\]/,/^\[/ { /^\"dinput8\"=\"native,builtin\"$/p; }' \
			"$user_reg")" ]]
}

set_dll_override()
{
	local user_reg="$1"
	local registry_temp
	local user_reg_dir="${user_reg%/user.reg}"

	[[ -d "$user_reg_dir" ]] || return 1
	registry_temp="$(mktemp "$user_reg.XXXXXX")" || return 1

	if [[ ! -f "$user_reg" ]]; then
		if ! printf '%s\n' \
			'WINE REGISTRY Version 2' \
			'' \
			'[Software\\Wine\\DllOverrides]' \
			'"dinput8"="native,builtin"' > "$registry_temp"; then
			rm -f "$registry_temp"
			return 1
		fi
	elif [[ -n "$(sed -nE \
		'/^\[Software\\\\Wine\\\\DllOverrides\]/p' \
		"$user_reg")" ]]; then
		if [[ -n "$(sed -nE \
			'/^\[Software\\\\Wine\\\\DllOverrides\]/,/^\[/ { /^\"dinput8\"=/p; }' \
			"$user_reg")" ]]; then
			if ! sed -E \
				'/^\[Software\\\\Wine\\\\DllOverrides\]/,/^\[/ s/^\"dinput8\"=.*/\"dinput8\"=\"native,builtin\"/' \
				"$user_reg" > "$registry_temp"; then
				rm -f "$registry_temp"
				return 1
			fi
		else
			if ! sed -E \
				'/^\[Software\\\\Wine\\\\DllOverrides\]/a \"dinput8\"=\"native,builtin\"' \
				"$user_reg" > "$registry_temp"; then
				rm -f "$registry_temp"
				return 1
			fi
		fi
	else
		if ! sed -n 'p' "$user_reg" > "$registry_temp" ||
			! printf '%s\n' \
				'' \
				'[Software\\Wine\\DllOverrides]' \
				'"dinput8"="native,builtin"' >> "$registry_temp"; then
			rm -f "$registry_temp"
			return 1
		fi
	fi

	if ! mv "$registry_temp" "$user_reg"; then
		rm -f "$registry_temp"
		return 1
	fi
}

STEAM_CANDIDATES=(
	"$HOME/.steam/steam"
	"$HOME/.steam/root"
	"$HOME/.local/share/Steam"
	"$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)

for candidate in "${STEAM_CANDIDATES[@]}"; do
	if [[ -d "$candidate/steamapps" ]]; then
		STEAM_ROOT="$candidate"
		break
	fi
done

if [[ -z "$STEAM_ROOT" ]]; then
	for search_root in \
		"$HOME/.steam" \
		"$HOME/.local/share" \
		"$HOME/.var/app/com.valvesoftware.Steam"; do
		[[ -d "$search_root" ]] || continue
		library_file="$(find "$search_root" \
			-maxdepth 6 \
			-type f \
			-path '*/steamapps/libraryfolders.vdf' \
			-print -quit 2>/dev/null)"
		if [[ -n "$library_file" ]]; then
			STEAM_ROOT="${library_file%/steamapps/libraryfolders.vdf}"
			break
		fi
	done
fi

if [[ -z "$STEAM_ROOT" ]]; then
	info "Steam Root: None"
	info "Steam libraries: None"
	info "Trackmania: None"
	die "Steam was not found."
fi

info "Steam Root: $STEAM_ROOT"

LIBRARIES=()
add_library "$STEAM_ROOT"

LIBRARY_FILE="$STEAM_ROOT/steamapps/libraryfolders.vdf"
if [[ -f "$LIBRARY_FILE" ]]; then
	while IFS= read -r library; do
		library="${library//\\\\/\\}"
		add_library "$library"
	done < <(
		read_vdf path "$LIBRARY_FILE"
	)
fi

library_indexes="$(printf '%s,' "${!LIBRARIES[@]}")"
library_indexes="${library_indexes%,}"
info "Steam libraries: ${library_indexes:-None}"
for index in "${!LIBRARIES[@]}"; do
	info "Steam library $index: ${LIBRARIES[$index]}"
done

APP_MANIFEST=""
for library in "${LIBRARIES[@]}"; do
	manifest="$library/steamapps/appmanifest_${APPID}.acf"
	[[ -f "$manifest" ]] || continue

	install_directory="$(read_vdf installdir "$manifest")"
	[[ -n "$install_directory" ]] || continue

	candidate="$library/steamapps/common/$install_directory"
	if [[ -f "$candidate/Trackmania.exe" ]]; then
		TRACKMANIA_DIR="$candidate"
		APP_MANIFEST="$manifest"
		break
	fi
done

if [[ -z "$TRACKMANIA_DIR" ]]; then
	info "Trackmania: None"
	info "Trackmania manifest: None"
	die "The script did not find Trackmania for Steam AppID $APPID."
fi

info "Trackmania: $TRACKMANIA_DIR"
info "Trackmania manifest: $APP_MANIFEST"

GAME_LIBRARY="${APP_MANIFEST%/steamapps/appmanifest_"${APPID}".acf}"
COMPAT_DATA_PATH=""
for library in "${LIBRARIES[@]}"; do
	candidate="$library/steamapps/compatdata/$APPID"
	if [[ -d "$candidate/pfx" ]]; then
		COMPAT_DATA_PATH="$candidate"
		break
	fi
done
if [[ -z "$COMPAT_DATA_PATH" ]]; then
	COMPAT_DATA_PATH="$GAME_LIBRARY/steamapps/compatdata/$APPID"
fi
USER_REG="$COMPAT_DATA_PATH/pfx/user.reg"

OPENPLANET_DIR="$TRACKMANIA_DIR/Openplanet"
LOADER_FILE="$TRACKMANIA_DIR/dinput8.dll"
OPENPLANET_MODULE_FILE="$TRACKMANIA_DIR/Openplanet.dll"

if [[ -e "$OPENPLANET_DIR" ]]; then
	info "Openplanet: $OPENPLANET_DIR"
else
	info "Openplanet: None"
fi
if [[ -e "$LOADER_FILE" ]]; then
	info "dinput8.dll: $LOADER_FILE"
else
	info "dinput8.dll: None"
fi
if [[ -e "$OPENPLANET_MODULE_FILE" ]]; then
	info "Openplanet.dll: $OPENPLANET_MODULE_FILE"
else
	info "Openplanet.dll: None"
fi
if has_dll_override "$USER_REG"; then
	info "Proton dinput8 override: native,builtin"
else
	info "Proton dinput8 override: None"
fi

if [[ "$STATUS_ONLY" -eq 1 ]]; then
	exit 0
fi

if [[ -d "$OPENPLANET_DIR" ]] &&
	[[ -f "$LOADER_FILE" ]] &&
	[[ -f "$OPENPLANET_MODULE_FILE" ]] &&
   [[ "$FORCE" -eq 0 ]]; then
	if has_dll_override "$USER_REG"; then
		warn "Openplanet is already installed. Use --force to install again."
		exit 0
	fi
	warn "Openplanet is installed, but the Proton dinput8 override is missing."
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
chmod 700 "$TMP_ROOT"
info "Temporary directory: $TMP_ROOT"

INSTALLER="$TMP_ROOT/OpenplanetNext.exe"
INSTALLER_PARTIAL="$INSTALLER.partial"
DOWNLOAD_PAGE="$TMP_ROOT/download.html"
STAGE="$TMP_ROOT/stage"
mkdir -p "$STAGE"
info "Download file: $INSTALLER"
info "Download page: $DOWNLOAD_PAGE_URL"
info "Staging directory: $STAGE"

info "Read the Openplanet download page."
if ! curl \
	--fail-with-body \
	--location \
	--proto '=https' \
	--tlsv1.2 \
	--connect-timeout 15 \
	--max-time 300 \
	--retry 5 \
	--retry-delay 2 \
	--retry-max-time 120 \
	--user-agent 'Mozilla/5.0' \
	--silent \
	--show-error \
	--output "$DOWNLOAD_PAGE" \
	"$DOWNLOAD_PAGE_URL"; then
	die "The script did not read the Openplanet download page."
fi

DOWNLOAD_URL="$(sed -nE \
	's/.*href="(https:\/\/openplanet\.dev\/download\/get\?id=[0-9]+)".*/\1/p' \
	"$DOWNLOAD_PAGE" | sed -n '1p')"
[[ -n "$DOWNLOAD_URL" ]] ||
	die "The Openplanet download page has no archive link."

	info "Download URL: $DOWNLOAD_URL"
warn "Download Openplanet."
if ! curl \
	--fail-with-body \
	--location \
	--proto '=https' \
	--tlsv1.2 \
	--connect-timeout 15 \
	--max-time 300 \
	--retry 5 \
	--retry-delay 2 \
	--retry-max-time 120 \
	--user-agent 'Mozilla/5.0' \
	--referer "$DOWNLOAD_PAGE_URL" \
	--silent \
	--show-error \
	--output "$INSTALLER_PARTIAL" \
	"$DOWNLOAD_URL"; then
	rm -f "$INSTALLER_PARTIAL"
	die "The script did not download Openplanet."
fi
mv "$INSTALLER_PARTIAL" "$INSTALLER"

DOWNLOAD_SIZE="$(wc -c < "$INSTALLER")"
if (( DOWNLOAD_SIZE < 102400 )); then
	die "The downloaded file is too small."
fi
if (( DOWNLOAD_SIZE > 500 * 1024 * 1024 )); then
	die "The downloaded file is too large."
fi
info "Downloaded bytes: $DOWNLOAD_SIZE"

info "Check the Openplanet archive."
if ! "$SEVENZIP" t "$INSTALLER" >/dev/null; then
	info "Archive test: Failed"
	die "The downloaded file is not a valid Openplanet archive."
fi
info "Archive test: Passed"

warn "Extract Openplanet to a temporary directory."
if ! "$SEVENZIP" x "$INSTALLER" "-o$STAGE" -y >/dev/null; then
	info "Archive extraction: Failed"
	die "The script did not extract Openplanet."
fi
info "Archive extraction: Passed"

OPENPLANET_DLL="$(
	find "$STAGE" -type f -iname dinput8.dll -print -quit
)"
[[ -n "$OPENPLANET_DLL" ]] ||
	die "The archive does not contain dinput8.dll."

PAYLOAD_ROOT="${OPENPLANET_DLL%/*}"
OPENPLANET_MODULE_SOURCE="$PAYLOAD_ROOT/Openplanet.dll"
[[ -f "$OPENPLANET_MODULE_SOURCE" ]] ||
	die "The archive does not contain Openplanet.dll."
OPENPLANET_PAYLOAD="$PAYLOAD_ROOT/Openplanet"
[[ -d "$OPENPLANET_PAYLOAD" ]] ||
	die "The archive does not contain Openplanet files."
[[ -n "$(find "$OPENPLANET_PAYLOAD" -type f -print -quit)" ]] ||
	die "The Openplanet payload does not contain files."
info "Openplanet payload: $PAYLOAD_ROOT"

warn "Set the Proton dinput8 override."
if ! set_dll_override "$USER_REG"; then
	die "The Proton prefix was not found or could not be updated. Start Trackmania once with Proton, close it, then start this script again."
fi
info "Proton dinput8 override: native,builtin"

BACKUP_DIR=""
if [[ -e "$OPENPLANET_DIR" || -e "$LOADER_FILE" || -e "$OPENPLANET_MODULE_FILE" ]]; then
	BACKUP_DIR="$(mktemp -d "$TRACKMANIA_DIR/.openplanet-backup.XXXXXX")"
	warn "Back up the current Openplanet files."

	for path in "$OPENPLANET_DIR" "$LOADER_FILE" "$OPENPLANET_MODULE_FILE"; do
		[[ -e "$path" ]] && cp -a "$path" "$BACKUP_DIR/"
	done
fi
info "Backup: ${BACKUP_DIR:-None}"

warn "Install Openplanet."
mkdir -p "$OPENPLANET_DIR"
cp -a "$OPENPLANET_PAYLOAD/." "$OPENPLANET_DIR/"
cp -a "$PAYLOAD_ROOT/dinput8.dll" "$LOADER_FILE"
cp -a "$OPENPLANET_MODULE_SOURCE" "$OPENPLANET_MODULE_FILE"

[[ -d "$OPENPLANET_DIR" && -f "$LOADER_FILE" && -r "$LOADER_FILE" &&
	-f "$OPENPLANET_MODULE_FILE" && -r "$OPENPLANET_MODULE_FILE" ]] ||
	die "The Openplanet files are not complete."
info "Installed Openplanet: $OPENPLANET_DIR"
info "Installed dinput8.dll: $LOADER_FILE"
info "Installed Openplanet.dll: $OPENPLANET_MODULE_FILE"

echo
echo "Openplanet is ready."
info "Steam launch options: Unchanged"
echo
echo "Launch Trackmania from Steam."
echo "Press F3 to open Openplanet."

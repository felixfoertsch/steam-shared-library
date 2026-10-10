#!/usr/bin/env bash
# steam-shared — launch Steam with per-user Proton prefix isolation
#
# Bind per-user Proton prefixes over shared library's compatdata path.
# Do not inherit shared prefixes: their ownership breaks Proton updates
# inside unprivileged user namespaces. Game files remain shared.

set -euo pipefail

SHARED_LIBRARY="/opt/steam"
SHARED_COMPATDATA="$SHARED_LIBRARY/steamapps/compatdata"
STATE_DIR="$HOME/.local/share/steam-shared"
USER_COMPATDATA="$STATE_DIR/compatdata"

# --- preflight checks ---

if [[ ! -d "$SHARED_COMPATDATA" ]]; then
	echo "steam-shared: shared library not found at $SHARED_COMPATDATA" >&2
	echo "steam-shared: run the activate script first (nix run .#activate)" >&2
	exit 1
fi

if ! id -nG | grep -qw steamshare; then
	echo "steam-shared: current user is not in the 'steamshare' group" >&2
	echo "steam-shared: run: sudo usermod -aG steamshare $(whoami)" >&2
	exit 1
fi

if ! command -v bwrap &>/dev/null; then
	echo "steam-shared: bubblewrap (bwrap) is not installed" >&2
	exit 1
fi

# --- detect Steam installation (prefer native over Flatpak) ---

STEAM_CMD=()
if [[ -x /usr/bin/steam ]]; then
	STEAM_CMD=(/usr/bin/steam)
elif command -v flatpak &>/dev/null && flatpak info com.valvesoftware.Steam &>/dev/null; then
	# grant Flatpak access to the shared library
	flatpak override --user --filesystem="$SHARED_LIBRARY" com.valvesoftware.Steam 2>/dev/null
	STEAM_CMD=(flatpak run com.valvesoftware.Steam)
else
	echo "steam-shared: no Steam installation found" >&2
	echo "steam-shared: install native Steam (pacman -S steam) or Flatpak Steam" >&2
	exit 1
fi

mkdir -p "$USER_COMPATDATA"

# Native games keep single-instance locks in /tmp; never share those across users.
# Retain desktop authentication and X11 sockets while hiding host temporary files.
TMP_BINDS=()
if [[ -d /tmp/.X11-unix ]]; then
	TMP_BINDS+=(--ro-bind /tmp/.X11-unix /tmp/.X11-unix)
fi
if [[ ${XAUTHORITY:-} == /tmp/* ]]; then
	if [[ ! -f "$XAUTHORITY" ]]; then
		echo "steam-shared: temporary Xauthority file is missing" >&2
		exit 1
	fi
	TMP_BINDS+=(--ro-bind "$XAUTHORITY" "$XAUTHORITY")
fi

exec bwrap \
	--dev-bind / / \
	--bind "$USER_COMPATDATA" "$SHARED_COMPATDATA" \
	--tmpfs /tmp \
	--setenv TMPDIR /tmp \
	"${TMP_BINDS[@]}" \
	-- "${STEAM_CMD[@]}" "$@"

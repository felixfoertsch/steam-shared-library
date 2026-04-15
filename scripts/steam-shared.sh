#!/usr/bin/env bash
# steam-shared — launch Steam with per-user Proton prefix isolation
#
# Uses bubblewrap to overlay /opt/steam/steamapps/compatdata/ with a
# per-user directory. Writes (Proton prefixes) go to the user's home,
# reads fall through to the shared library. Each user gets their own
# mount namespace — concurrent sessions are fully isolated.

set -euo pipefail

SHARED_LIBRARY="/opt/steam"
SHARED_COMPATDATA="$SHARED_LIBRARY/steamapps/compatdata"
OVERLAY_DIR="$HOME/.local/share/steam-shared"
OVERLAY_UPPER="$OVERLAY_DIR/upper"
OVERLAY_WORK="$OVERLAY_DIR/work"

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

# --- set up per-user overlay dirs ---

mkdir -p "$OVERLAY_UPPER" "$OVERLAY_WORK"

# clean stale overlayfs work dir (causes "Device or resource busy")
# overlayfs sets work/work to mode 0000 — must chmod before removing
if [[ -d "$OVERLAY_WORK/work" ]]; then
	chmod -R u+rwx "$OVERLAY_WORK/work" 2>/dev/null
	rm -rf "$OVERLAY_WORK/work"
fi

# --- launch Steam inside bwrap with overlay ---

exec bwrap \
	--dev-bind / / \
	--overlay-src "$SHARED_COMPATDATA" \
	--overlay "$OVERLAY_UPPER" "$OVERLAY_WORK" "$SHARED_COMPATDATA" \
	-- "${STEAM_CMD[@]}" "$@"

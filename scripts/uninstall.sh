#!/usr/bin/env bash
# uninstall.sh — remove the shared Steam library system
# Requires sudo. Safe to run multiple times.
set -euo pipefail

STEAM_GROUP="steamshare"
STEAM_DIR="/opt/steam"

if [[ $EUID -ne 0 ]]; then
	echo "error: run this script with sudo" >&2
	exit 1
fi

echo "[1/5] Remove launcher"
rm -f /usr/local/bin/steam-shared
echo "  done"

echo "[2/5] Remove .desktop override"
rm -f /usr/local/share/applications/steam.desktop
echo "  done"

echo "[3/5] Remove permission watcher"
if systemctl is-active --quiet steam-fix-perms.path 2>/dev/null; then
	systemctl disable --now steam-fix-perms.path
fi
rm -f /etc/systemd/system/steam-fix-perms.path
rm -f /etc/systemd/system/steam-fix-perms.service
rm -f /usr/local/bin/steam-fix-perms
systemctl daemon-reload 2>/dev/null
echo "  done"

echo "[4/5] Remove steamshare group"
if getent group "$STEAM_GROUP" >/dev/null 2>&1; then
	while IFS= read -r u; do
		[[ -z "$u" ]] && continue
		gpasswd -d "$u" "$STEAM_GROUP" >/dev/null 2>&1 || true
	done < <(getent group "$STEAM_GROUP" | cut -d: -f4 | tr ',' '\n')
	groupdel "$STEAM_GROUP" 2>/dev/null || true
	echo "  removed group $STEAM_GROUP"
else
	echo "  group does not exist"
fi

echo "[5/5] Shared library directory"
if [[ -d "$STEAM_DIR" ]]; then
	echo "  $STEAM_DIR exists ($(du -sh "$STEAM_DIR" 2>/dev/null | cut -f1) used)"
	echo "  to remove: sudo rm -rf $STEAM_DIR"
	echo "  (not removed automatically — contains game data)"
else
	echo "  does not exist"
fi

echo
echo "========================================"
echo " Uninstall complete."
echo
echo " Each user should:"
echo "   1. Remove $STEAM_DIR from Steam → Settings → Storage"
echo "   2. Optionally remove ~/.local/share/steam-shared/"
echo "========================================"

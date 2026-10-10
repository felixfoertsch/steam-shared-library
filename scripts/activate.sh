#!/usr/bin/env bash
# activate.sh — set up the shared Steam library system
# Requires sudo. Idempotent — safe to re-run.
set -euo pipefail

STEAM_GROUP="steamshare"
STEAM_DIR="/opt/steam"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- preflight ---

if [[ $EUID -ne 0 ]]; then
	echo "error: run this script with sudo" >&2
	exit 1
fi

if ! command -v bwrap &>/dev/null; then
	echo "error: bubblewrap (bwrap) is not installed" >&2
	echo "  arch/cachyos: pacman -S bubblewrap" >&2
	echo "  debian/ubuntu: apt install bubblewrap" >&2
	exit 1
fi

echo "[1/7] Group"
if ! getent group "$STEAM_GROUP" >/dev/null; then
	groupadd "$STEAM_GROUP"
	echo "  created group $STEAM_GROUP"
else
	echo "  group $STEAM_GROUP exists"
fi

echo "[2/7] Shared library directory"
mkdir -p "$STEAM_DIR/steamapps/compatdata"
find "$STEAM_DIR" -type d -exec chmod 2775 {} +
chown -R root:"$STEAM_GROUP" "$STEAM_DIR"
setfacl -R -m g:"$STEAM_GROUP":rwx "$STEAM_DIR"
setfacl -dR -m g:"$STEAM_GROUP":rwx "$STEAM_DIR"
echo "  $STEAM_DIR ready (setgid + ACLs)"

echo "[3/7] Preserve existing compatdata prefixes"
echo "  shared prefixes retained; launcher uses private per-user prefixes"

echo "[4/7] Install launcher"
install -m 755 "$PROJECT_DIR/scripts/steam-shared.sh" /usr/local/bin/steam-shared
echo "  /usr/local/bin/steam-shared installed"

echo "[5/7] Install .desktop override"
mkdir -p /usr/local/share/applications
install -m 644 "$PROJECT_DIR/desktop/steam.desktop" /usr/local/share/applications/steam.desktop
echo "  .desktop override installed"

echo "[6/7] Install permission watcher"
install -m 755 "$PROJECT_DIR/scripts/fix-perms.sh" /usr/local/bin/steam-fix-perms

cat > /etc/systemd/system/steam-fix-perms.service << 'UNIT'
[Unit]
Description=Fix shared Steam library permissions after pressure-vessel changes

[Service]
Type=oneshot
ExecStart=/usr/local/bin/steam-fix-perms
UNIT

cat > /etc/systemd/system/steam-fix-perms.path << UNIT
[Unit]
Description=Watch shared Steam library for permission changes

[Path]
PathChanged=$STEAM_DIR/steamapps/common
PathChanged=$STEAM_DIR/steamapps/shadercache
TriggerLimitIntervalSec=10
TriggerLimitBurst=1

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now steam-fix-perms.path
echo "  permission watcher enabled"

echo "[7/7] Fix current permissions"
bash "$PROJECT_DIR/scripts/fix-perms.sh"
echo "  permissions fixed"

echo
echo "========================================"
echo " Activation complete."
echo
echo " Shared library:  $STEAM_DIR"
echo " Launcher:        /usr/local/bin/steam-shared"
echo " Desktop file:    /usr/local/share/applications/steam.desktop"
echo
echo " To add a user:"
echo "   sudo usermod -aG $STEAM_GROUP <username>"
echo "   (user must log out and back in)"
echo
echo " Each user must:"
echo "   1. Launch Steam (it uses the shared library launcher automatically)"
echo "   2. Steam → Settings → Storage → add $STEAM_DIR"
echo "   3. Use any Proton version — isolation is automatic"
echo "========================================"

#!/usr/bin/env bash
# fix-perms.sh — fix permissions on the shared Steam library
# Called by systemd path unit when pressure-vessel creates dirs with
# restrictive permissions. Also safe to run manually.

set -uo pipefail

STEAM_DIR="/opt/steam"
STEAM_GROUP="steamshare"

# fix dirs missing group rwx (pressure-vessel tmp-*, var/, etc.)
find "$STEAM_DIR/steamapps" -type d ! -perm -g+rwx -exec chmod 2775 {} +

# fix files missing group rw
find "$STEAM_DIR/steamapps" -type f ! -perm -g+rw -exec chmod g+rw {} +

# restore execute bits on ELF binaries and shebang scripts
find "$STEAM_DIR/steamapps" -type f ! -perm -a+x -exec sh -c '
	for f; do
		head -c4 "$f" 2>/dev/null | grep -qP "^\x7fELF|^#!" && chmod a+x "$f"
	done
' _ {} +

# fix group ownership (skip broken symlinks)
find "$STEAM_DIR/steamapps" -not -type l ! -group "$STEAM_GROUP" -exec chown root:"$STEAM_GROUP" {} +
find "$STEAM_DIR/steamapps" -type l ! -group "$STEAM_GROUP" -exec chown -h root:"$STEAM_GROUP" {} + 2>/dev/null || true

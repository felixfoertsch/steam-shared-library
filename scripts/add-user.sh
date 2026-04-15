#!/usr/bin/env bash
# add-user.sh — add a user to the shared Steam library
# Requires sudo.
set -euo pipefail

STEAM_GROUP="steamshare"

if [[ $EUID -ne 0 ]]; then
	echo "error: run this script with sudo" >&2
	exit 1
fi

if [[ $# -eq 0 ]]; then
	echo "usage: $0 <username> [username...]" >&2
	exit 1
fi

if ! getent group "$STEAM_GROUP" >/dev/null 2>&1; then
	echo "error: group '$STEAM_GROUP' does not exist — run activate first" >&2
	exit 1
fi

for user in "$@"; do
	if ! id "$user" &>/dev/null; then
		echo "  $user: user does not exist, skipping" >&2
		continue
	fi

	if id -nG "$user" | grep -qw "$STEAM_GROUP"; then
		echo "  $user: already in $STEAM_GROUP"
	else
		usermod -aG "$STEAM_GROUP" "$user"
		echo "  $user: added to $STEAM_GROUP (log out and back in to take effect)"
	fi
done

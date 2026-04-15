#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/activate.sh"

if ! grep -Fq 'Desktop file:    /usr/local/share/applications/steam.desktop' "$SCRIPT"; then
	echo "activate summary should reference /usr/local/share/applications/steam.desktop"
	exit 1
fi

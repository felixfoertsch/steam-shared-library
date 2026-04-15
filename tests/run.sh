#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test_file in "$SCRIPT_DIR"/*.test.sh; do
	echo "==> $(basename "$test_file")"
	bash "$test_file"
done

echo "all tests passed"

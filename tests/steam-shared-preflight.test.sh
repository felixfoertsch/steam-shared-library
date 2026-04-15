#!/usr/bin/env bash
# Verify steam-shared preflight fails cleanly when the user is not in
# the steamshare group. We force that condition by overriding `id` via
# PATH so the test is deterministic regardless of the host environment.
# Without this shim, a developer who is already in the steamshare group
# and has /opt/steam activated would actually launch Steam from the test.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/steam-shared.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-nG" ]]; then
	echo "users"
	exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod +x "$TMP_DIR/id"

set +e
OUTPUT="$(PATH="$TMP_DIR:$PATH" HOME="$TMP_DIR" bash "$SCRIPT" 2>&1)"
STATUS=$?
set -e

if [[ $STATUS -eq 0 ]]; then
	echo "expected preflight failure, got success"
	echo "output: $OUTPUT"
	exit 1
fi

if [[ "$OUTPUT" == *"steam-shared: shared library not found at /opt/steam/steamapps/compatdata"* ]]; then
	exit 0
fi

if [[ "$OUTPUT" == *"steam-shared: current user is not in the 'steamshare' group"* ]]; then
	exit 0
fi

echo "expected preflight failure about missing shared path or missing group"
echo "actual output: $OUTPUT"
exit 1

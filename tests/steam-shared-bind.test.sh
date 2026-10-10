#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/library" "$TMP_DIR/home"
# Substitute host boundaries only; exercise actual launcher decisions.
sed -e "s|/opt/steam|$TMP_DIR/library|g" -e "s|/usr/bin/steam|$TMP_DIR/bin/steam|g" "$ROOT_DIR/scripts/steam-shared.sh" > "$TMP_DIR/launcher"
mkdir -p "$TMP_DIR/library/steamapps/compatdata"
printf '#!/usr/bin/env bash\necho steamshare\n' > "$TMP_DIR/bin/id"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/steam"
cat > "$TMP_DIR/bin/bwrap" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CAPTURE"
EOF
chmod +x "$TMP_DIR/bin/"*
export HOME="$TMP_DIR/home" PATH="$TMP_DIR/bin:$PATH" CAPTURE="$TMP_DIR/args"
bash "$TMP_DIR/launcher"
grep -Fx -- '--bind' "$CAPTURE"
if grep -q -- '--overlay' "$CAPTURE"; then
	echo 'unexpected overlay mount' >&2
	exit 1
fi
grep -Fx "$HOME/.local/share/steam-shared/compatdata" "$CAPTURE"
test -d "$HOME/.local/share/steam-shared/compatdata"
grep -Fx -- '--tmpfs' "$CAPTURE"
grep -Fx -- '/tmp' "$CAPTURE"
grep -Fx -- 'TMPDIR' "$CAPTURE"
# Temporary Xauthority must remain available after hiding host /tmp.
XAUTHORITY="$(mktemp /tmp/steam-shared-test-auth.XXXXXX)"
export XAUTHORITY
bash "$TMP_DIR/launcher"
grep -Fx "$XAUTHORITY" "$CAPTURE"
rm -- "$XAUTHORITY"

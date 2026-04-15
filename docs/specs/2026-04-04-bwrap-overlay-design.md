# Steam Shared Library: Bubblewrap Overlay Approach

**Date:** 2026-04-04
**Status:** Approved

## Problem

Multiple users on a shared Linux machine need to play games from a single Steam library (`/opt/steam/`) without Proton prefix ownership conflicts. Steam mixes shared state (game files in `common/`) with per-user state (Wine prefixes in `compatdata/`) in the same directory. Every Proton variant writes to `compatdata/` — and when two users share the same prefix, Proton/Wine fails with ownership errors (`wineserver: pfx is not owned by you`).

The previous approach (a Proton compatibility tool wrapper that redirected `STEAM_COMPAT_DATA_PATH`) was brittle: it required manual per-game selection, any per-game Proton override bypassed it, and Steam sometimes wrote to the original path before the wrapper ran.

## Solution

Use `bubblewrap` (bwrap) to mount a kernel overlay on `/opt/steam/steamapps/compatdata/` per user. Each user launches Steam through a wrapper script that creates a private mount namespace via bwrap. Writes to compatdata go to a per-user upper layer directory. Reads fall through to the shared lower layer. Game files (`common/`, `shadercache/`, etc.) are not overlaid — they remain shared and writable by all `steamshare` group members.

This is transparent to Steam and every Proton variant. No compatibility tool selection, no environment variable hacks, no per-game configuration.

## How It Works

```
/opt/steam/steamapps/
├── common/            ← shared game files (real filesystem, group writable)
├── shadercache/       ← shared shader cache (real filesystem)
├── compatdata/        ← OVERLAID per-user via bwrap
│   ├── <appid>/      ← lower layer: shared (mostly empty dirs Steam creates)
│   └── ...           ← upper layer: ~/.local/share/steam-shared/upper/
└── ...

Per user (inside bwrap mount namespace):
  /opt/steam/steamapps/compatdata/  ← overlay mount
    lower:  /opt/steam/steamapps/compatdata/        (shared, read-through)
    upper:  ~/.local/share/steam-shared/upper/       (per-user writes)
    work:   ~/.local/share/steam-shared/work/        (overlayfs workdir)
```

When a user launches a Proton game:
1. Steam sets `STEAM_COMPAT_DATA_PATH=/opt/steam/steamapps/compatdata/<appid>`
2. Proton creates/opens the prefix at that path
3. The kernel overlay redirects the write to `~/.local/share/steam-shared/upper/<appid>/`
4. Other users are unaffected — they have their own mount namespace with their own upper layer

## Target Platforms

- Linux (Arch/CachyOS) with native Steam — primary target
- Linux with Flatpak Steam — supported via `--filesystem=/opt/steam` override
- NixOS — future, via NixOS module output from the same flake

## Prerequisites

- `bubblewrap` (already installed as Flatpak dependency on most systems)
- `acl` package for `setfacl`
- Kernel overlay support (standard on all modern kernels)
- Native Steam (`pacman -S steam`) or Flatpak Steam

## Project Structure

```
steam-shared-library/
├── flake.nix                      ← Nix flake: outputs activate + uninstall packages
├── flake.lock
├── scripts/
│   ├── activate.sh                ← system setup (requires sudo)
│   ├── uninstall.sh               ← reversal (requires sudo)
│   └── steam-shared.sh            ← per-user Steam launcher
├── desktop/
│   └── steam-shared.desktop       ← .desktop override for Steam
├── README.md
└── docs/
    └── specs/
        └── 2026-04-04-bwrap-overlay-design.md
```

## Components

### 1. Activation Script (`nix run .#activate`)

Requires sudo. Idempotent — safe to re-run.

**Actions:**
- Create `steamshare` group if it doesn't exist
- Create `/opt/steam/steamapps/compatdata/` with setgid `2775` and group ACLs for `steamshare`
- Wipe all contents of `/opt/steam/steamapps/compatdata/*/` (clean slate — stale shared prefixes)
- Install `steam-shared` launcher script to `/usr/local/bin/steam-shared`
- Install `steam-shared.desktop` to `/usr/local/share/applications/` (shadows system `steam.desktop`)
- Verify `bubblewrap` is installed (error if not)

**Does NOT:**
- Add users to the steamshare group (manual: `sudo usermod -aG steamshare <user>`)
- Install Steam itself
- Install a permission watcher (ACLs + setgid should suffice)

### 2. Steam Launcher Script (`/usr/local/bin/steam-shared`)

Runs as the logged-in user. No root required.

```bash
#!/bin/bash
set -euo pipefail

OVERLAY_DIR="$HOME/.local/share/steam-shared"
SHARED_COMPATDATA="/opt/steam/steamapps/compatdata"

mkdir -p "$OVERLAY_DIR/upper" "$OVERLAY_DIR/work"

# Detect Steam installation: prefer native over Flatpak
STEAM_CMD=()
if [ -x /usr/bin/steam ]; then
	STEAM_CMD=(/usr/bin/steam)
elif flatpak info com.valvesoftware.Steam &>/dev/null; then
	flatpak override --user --filesystem=/opt/steam com.valvesoftware.Steam 2>/dev/null
	STEAM_CMD=(flatpak run com.valvesoftware.Steam)
else
	echo "steam-shared: no Steam installation found (checked /usr/bin/steam and Flatpak)" >&2
	exit 1
fi

exec bwrap \
	--dev-bind / / \
	--overlay-src "$SHARED_COMPATDATA" \
	--overlay "$OVERLAY_DIR/upper" "$OVERLAY_DIR/work" "$SHARED_COMPATDATA" \
	-- "${STEAM_CMD[@]}" "$@"
```

### 3. Desktop File Override (`/usr/local/share/applications/steam-shared.desktop`)

Shadows the system-installed `steam.desktop` by using the same `Name` and higher-priority location. Uses the same icon and categories so it looks identical in the app menu.

Key fields:
- `Exec=steam-shared %U`
- `Name=Steam`
- `Icon=steam` (uses system Steam icon)

### 4. Uninstall Script (`nix run .#uninstall`)

Requires sudo. Reverses everything the activation script does:
- Remove `/usr/local/bin/steam-shared`
- Remove `/usr/local/share/applications/steam-shared.desktop`
- Remove `steamshare` group (and membership)
- Print instructions for optional manual cleanup (`/opt/steam/`, per-user `~/.local/share/steam-shared/`)

Does NOT remove Steam itself or per-user save data.

### 5. Nix Flake

Outputs:
- `packages.<system>.activate` — activation script (wraps `scripts/activate.sh`)
- `packages.<system>.uninstall` — uninstall script (wraps `scripts/uninstall.sh`)
- Future: `nixosModules.default` — native NixOS module for declarative system config

## Steam Detection Logic

The launcher prefers native Steam over Flatpak Steam:
1. If `/usr/bin/steam` exists → use native
2. Else if `flatpak info com.valvesoftware.Steam` succeeds → use Flatpak with `--filesystem=/opt/steam`
3. Else → error

If both are installed, native wins. This is documented in the README — having both installed is discouraged because it leads to two separate Steam configs, library confusion, and double disk usage.

## Flatpak Steam Specifics

Flatpak Steam runs inside its own sandbox. For the bwrap overlay to work:
- The Flatpak app needs filesystem access to `/opt/steam/` (granted via `flatpak override --user --filesystem=/opt/steam`)
- The bwrap overlay is set up OUTSIDE Flatpak's sandbox — bwrap creates the mount namespace first, then `flatpak run` inherits it
- Confirmed working: writes inside Flatpak's sandbox go through bwrap's overlay to the per-user upper layer

## Integration with Dotfiles

The dotfiles project (`~/.syncthing/dotfiles/`) integrates this via:
- `nix run github:felixfoertsch/steam-shared-library#activate` runs on Linux machines
- Old wrapper system cleanup is handled by `roles/legacy-cleanup/` in the Ansible playbook
- Users are added to `steamshare` group via the `managed-users` role's create flow

## Error Handling

- **bubblewrap not installed:** activation script checks and fails with clear error message
- **Steam not installed:** launcher script checks both native and Flatpak, fails with clear message
- **User not in steamshare group:** Steam launches but can't access `/opt/steam/` — standard permission denied from filesystem
- **Stale work dir:** overlayfs work directories can become stale (causes "Device or resource busy"). The launcher creates fresh dirs if the work dir contains a stale `work/` subdirectory.
- **/opt/steam/ doesn't exist:** activation script creates it; launcher checks and fails with clear message

## User Workflow

1. Admin runs `nix run .#activate`
2. Admin adds users to steamshare group: `sudo usermod -aG steamshare <user>`
3. User logs out and back in (for group membership)
4. User launches Steam normally via app menu or command line
5. Games install to `/opt/steam/` — visible to all users
6. Proton prefixes go to `~/.local/share/steam-shared/upper/<appid>/` — per-user, isolated
7. Multiple users can be logged in simultaneously (GDM user switching) — each has their own mount namespace

## Guided Gates

- **GG-1:** Run `nix run .#activate`, verify group/dir/ACLs/desktop file/launcher script created correctly
- **GG-2:** Launch Steam via the desktop entry, verify overlay is active (write to compatdata goes to upper layer)
- **GG-3:** Install a game from Steam, verify it lands in `/opt/steam/steamapps/common/` (shared, not overlaid)
- **GG-4:** Launch a Proton game with any Proton variant, verify prefix lands in `~/.local/share/steam-shared/upper/<appid>/` and NOT in `/opt/steam/steamapps/compatdata/<appid>/`
- **GG-5:** Create a second user, add to steamshare, launch Steam, verify shared games visible and prefix is isolated
- **GG-6:** Both users logged in via GDM simultaneously — both can access Steam without conflicts
- **GG-7:** Run `nix run .#uninstall`, verify clean removal of all artifacts

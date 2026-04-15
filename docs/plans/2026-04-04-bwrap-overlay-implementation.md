# Steam Shared Library (bwrap overlay) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the brittle Proton wrapper approach with a bubblewrap overlay on `/opt/steam/steamapps/compatdata/` that transparently gives each user their own Proton prefix directory.

**Architecture:** A Nix flake in `/path/to/steam-shared-library/` outputs two packages: `activate` (system setup with sudo) and `uninstall` (reversal). The activate script creates the steamshare group, shared directory with ACLs, a Steam launcher script that uses bwrap overlay, and a .desktop override. The old wrapper system is cleaned up via a legacy-cleanup script.

**Tech Stack:** Nix flakes, bash, bubblewrap, overlayfs, systemd (for .desktop), Ansible (legacy cleanup only)

---

## File Structure

### steam-shared-library repo (clean slate — all old files removed)

| File | Responsibility |
|------|---------------|
| `flake.nix` | Nix flake entry point: outputs activate + uninstall packages |
| `scripts/activate.sh` | System setup: group, dirs, ACLs, install launcher + .desktop |
| `scripts/uninstall.sh` | Reversal: remove launcher, .desktop, group |
| `scripts/steam-shared.sh` | Per-user Steam launcher with bwrap overlay |
| `desktop/steam-shared.desktop` | .desktop override that launches steam-shared |
| `README.md` | User-facing documentation |
| `docs/specs/2026-04-04-bwrap-overlay-design.md` | Design spec (already written) |
| `.project.toml` | Project metadata |
| `.gitignore` | Git ignore rules |

### Dotfiles repo (modifications)

| File | Change |
|------|--------|
| `roles/legacy-cleanup/tasks/main.yml` | Add tasks to remove old wrapper system |

---

### Task 1: Clean the repo

**Files:**
- Remove: all old files (`steam-setup.sh`, `steam-cleanup.sh`, `steam-fix-perms.sh`, `steam-ensure-wrapper.sh`, `steam-uninstall.sh`, `proton-shared-lib/`, `docs/plans/2026-03-10-*`)
- Keep: `docs/specs/2026-04-04-bwrap-overlay-design.md`, `.project.toml`, `.gitignore`

- [ ] **Step 1: Remove all old files**

```bash
cd /path/to/steam-shared-library
git rm steam-setup.sh steam-cleanup.sh steam-fix-perms.sh steam-ensure-wrapper.sh README.md
git rm -r proton-shared-lib/
git rm -r docs/plans/
rm -f steam-uninstall.sh .DS_Store
echo ".DS_Store" >> .gitignore
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p scripts desktop
```

- [ ] **Step 3: Update .project.toml**

```toml
[project]
name = "Steam Shared Library"
description = "Multi-user shared Steam library for Linux using bubblewrap overlay — per-user Proton prefixes with zero configuration."
status = "aktiv"
priority = "hoch"
location = "/path/to/steam-shared-library"

[dates]
created = "2026-03-01"
last_activity = "2026-04-04"

[notes]
next_steps = "Implement bwrap overlay approach, test with managed users"
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "remove old wrapper approach, prepare for bwrap overlay"
```

---

### Task 2: Steam launcher script

**Files:**
- Create: `scripts/steam-shared.sh`

The core of the solution. Detects native/Flatpak Steam, sets up bwrap overlay on compatdata, launches Steam.

- [ ] **Step 1: Create the launcher script**

```bash
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
if [[ -d "$OVERLAY_WORK/work" ]]; then
	rm -rf "$OVERLAY_WORK/work"
fi

# --- launch Steam inside bwrap with overlay ---

exec bwrap \
	--dev-bind / / \
	--overlay-src "$SHARED_COMPATDATA" \
	--overlay "$OVERLAY_UPPER" "$OVERLAY_WORK" "$SHARED_COMPATDATA" \
	-- "${STEAM_CMD[@]}" "$@"
```

- [ ] **Step 2: Make executable**

```bash
chmod 755 scripts/steam-shared.sh
```

- [ ] **Step 3: Test the launcher manually**

```bash
# Quick smoke test — verify bwrap overlay is set up (don't actually launch Steam GUI)
bash scripts/steam-shared.sh --help 2>&1 | head -5
# Should show Steam's help output, meaning it launched successfully inside bwrap
```

- [ ] **Step 4: Commit**

```bash
git add scripts/steam-shared.sh
git commit -m "add steam launcher with bwrap overlay on compatdata"
```

---

### Task 3: Desktop file override

**Files:**
- Create: `desktop/steam-shared.desktop`

- [ ] **Step 1: Create the .desktop file**

```ini
[Desktop Entry]
Name=Steam
Comment=Application for managing and playing games on Steam
Exec=steam-shared %U
Icon=steam
Terminal=false
Type=Application
Categories=Network;FileTransfer;Game;
MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
Actions=Store;Community;Library;Servers;Screenshots;News;Settings;BigPicture;Friends;

[Desktop Action Store]
Name=Store
Exec=steam-shared steam://store

[Desktop Action Community]
Name=Community
Exec=steam-shared steam://url/SteamIDControlPage

[Desktop Action Library]
Name=Library
Exec=steam-shared steam://open/games

[Desktop Action Servers]
Name=Servers
Exec=steam-shared steam://open/servers

[Desktop Action Screenshots]
Name=Screenshots
Exec=steam-shared steam://open/screenshots

[Desktop Action News]
Name=News
Exec=steam-shared steam://open/news

[Desktop Action Settings]
Name=Settings
Exec=steam-shared steam://open/settings

[Desktop Action BigPicture]
Name=Big Picture
Exec=steam-shared steam://open/bigpicture

[Desktop Action Friends]
Name=Friends
Exec=steam-shared steam://open/friends
```

- [ ] **Step 2: Commit**

```bash
git add desktop/steam-shared.desktop
git commit -m "add .desktop override for steam-shared launcher"
```

---

### Task 4: Activation script

**Files:**
- Create: `scripts/activate.sh`

- [ ] **Step 1: Create the activation script**

```bash
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

echo "[1/5] Group"
if ! getent group "$STEAM_GROUP" >/dev/null; then
	groupadd "$STEAM_GROUP"
	echo "  created group $STEAM_GROUP"
else
	echo "  group $STEAM_GROUP exists"
fi

echo "[2/5] Shared library directory"
mkdir -p "$STEAM_DIR/steamapps/compatdata"
find "$STEAM_DIR" -type d -exec chmod 2775 {} +
chown -R root:"$STEAM_GROUP" "$STEAM_DIR"
setfacl -R -m g:"$STEAM_GROUP":rwx "$STEAM_DIR"
setfacl -dR -m g:"$STEAM_GROUP":rwx "$STEAM_DIR"
echo "  $STEAM_DIR ready (setgid + ACLs)"

echo "[3/5] Clean stale compatdata prefixes"
# remove all contents inside compatdata app dirs (not the dirs themselves —
# Steam recreates empty ones and they're harmless as lower-layer placeholders)
find "$STEAM_DIR/steamapps/compatdata" -mindepth 2 -delete 2>/dev/null || true
echo "  compatdata cleaned"

echo "[4/5] Install launcher"
install -m 755 "$PROJECT_DIR/scripts/steam-shared.sh" /usr/local/bin/steam-shared
echo "  /usr/local/bin/steam-shared installed"

echo "[5/5] Install .desktop override"
mkdir -p /usr/local/share/applications
install -m 644 "$PROJECT_DIR/desktop/steam-shared.desktop" /usr/local/share/applications/steam-shared.desktop
echo "  .desktop override installed"

echo
echo "========================================"
echo " Activation complete."
echo
echo " Shared library:  $STEAM_DIR"
echo " Launcher:        /usr/local/bin/steam-shared"
echo " Desktop file:    /usr/local/share/applications/steam-shared.desktop"
echo
echo " To add a user:"
echo "   sudo usermod -aG $STEAM_GROUP <username>"
echo "   (user must log out and back in)"
echo
echo " Each user must:"
echo "   1. Launch Steam (it will use the shared library launcher automatically)"
echo "   2. Steam → Settings → Storage → add $STEAM_DIR"
echo "   3. Use any Proton version — isolation is automatic"
echo "========================================"
```

- [ ] **Step 2: Make executable**

```bash
chmod 755 scripts/activate.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/activate.sh
git commit -m "add activation script for system-level setup"
```

---

### Task 5: Uninstall script

**Files:**
- Create: `scripts/uninstall.sh`

- [ ] **Step 1: Create the uninstall script**

```bash
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

echo "[1/4] Remove launcher"
rm -f /usr/local/bin/steam-shared
echo "  done"

echo "[2/4] Remove .desktop override"
rm -f /usr/local/share/applications/steam-shared.desktop
echo "  done"

echo "[3/4] Remove steamshare group"
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

echo "[4/4] Shared library directory"
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
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod 755 scripts/uninstall.sh
git add scripts/uninstall.sh
git commit -m "add uninstall script"
```

---

### Task 6: Nix flake

**Files:**
- Create: `flake.nix`

- [ ] **Step 1: Create the flake**

```nix
{
	description = "Multi-user shared Steam library for Linux using bubblewrap overlay";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
	};

	outputs = { self, nixpkgs, ... }:
		let
			supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
			forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
		in
		{
			packages = forAllSystems (system:
				let
					pkgs = nixpkgs.legacyPackages.${system};

					activate = pkgs.writeShellApplication {
						name = "steam-shared-activate";
						runtimeInputs = with pkgs; [ acl coreutils findutils ];
						text = ''
							exec "${self}/scripts/activate.sh" "$@"
						'';
					};

					uninstall = pkgs.writeShellApplication {
						name = "steam-shared-uninstall";
						runtimeInputs = with pkgs; [ coreutils ];
						text = ''
							exec "${self}/scripts/uninstall.sh" "$@"
						'';
					};
				in
				{
					inherit activate uninstall;
					default = activate;
				}
			);
		};
}
```

- [ ] **Step 2: Verify flake evaluates**

```bash
cd /path/to/steam-shared-library
nix flake check --no-build 2>&1
# Expected: warning about dirty tree, then "all checks passed!" or similar
```

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "add nix flake with activate and uninstall packages"
```

---

### Task 7: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

```markdown
# Steam Shared Library

Share one Steam game library across multiple Linux users with fully isolated Proton prefixes.

## The Problem

Steam stores Proton/Wine prefixes (`compatdata`) inside the game library folder. When multiple users share a library, they all write to the same prefix directory, causing:

- `wineserver: pfx is not owned by you`
- `PermissionError: os.chmod`
- `pressure-vessel: Permission denied`

## How It Works

Uses [bubblewrap](https://github.com/containers/bubblewrap) to create a per-user kernel overlay on `/opt/steam/steamapps/compatdata/`:

- **Game files** (`common/`, `shadercache/`) → shared directly, readable and writable by all group members
- **Proton prefixes** (`compatdata/`) → overlaid per-user via bwrap's mount namespace

Each user gets their own overlay. Writes go to `~/.local/share/steam-shared/upper/`. Reads fall through to the shared directory. Multiple users can be logged in simultaneously (GDM user switching) — each session has its own isolated mount namespace.

**No compatibility tool selection. No per-game configuration. Works with any Proton variant.**

## Prerequisites

- Linux with a modern kernel (overlay support)
- `bubblewrap` (`pacman -S bubblewrap` / `apt install bubblewrap`)
- `acl` package for `setfacl` (usually pre-installed)
- Steam (native package or Flatpak)
- Nix (for installation via flake)

## Installation

```bash
# install (requires sudo)
nix run github:felixfoertsch/steam-shared-library -- activate
# or from a local checkout:
sudo ./scripts/activate.sh
```

This creates:
- `steamshare` group
- `/opt/steam/` with correct permissions and ACLs
- `/usr/local/bin/steam-shared` launcher
- `.desktop` override so Steam launches through the shared launcher

## Setup

```bash
# add users to the shared library group
sudo usermod -aG steamshare <username>
# user must log out and back in for group membership

# each user: open Steam → Settings → Storage → add /opt/steam
# install games to /opt/steam — they're shared for all users
# use any Proton version — prefix isolation is automatic
```

## Steam Detection

The launcher prefers native Steam over Flatpak:

1. If `/usr/bin/steam` exists → native Steam
2. Else if Flatpak Steam is installed → Flatpak with filesystem access to `/opt/steam`
3. Else → error

**If both are installed, native wins.** Having both native and Flatpak Steam is discouraged — it leads to two separate configs, library confusion, and wasted disk space. Pick one.

## Uninstall

```bash
nix run github:felixfoertsch/steam-shared-library#uninstall
# or from a local checkout:
sudo ./scripts/uninstall.sh
```

This removes the launcher, .desktop override, and steamshare group. Game data at `/opt/steam/` and per-user prefixes at `~/.local/share/steam-shared/` are preserved (remove manually if desired).

## How It Works (Technical)

The Steam launcher (`steam-shared`) does:

1. Verify prerequisites (shared dir exists, user in steamshare group, bwrap installed)
2. Detect Steam installation (native or Flatpak)
3. Create per-user overlay directories (`~/.local/share/steam-shared/{upper,work}`)
4. Launch Steam inside a bwrap mount namespace with an overlay on `compatdata/`

```
bwrap --dev-bind / / \
    --overlay-src /opt/steam/steamapps/compatdata \
    --overlay ~/.local/share/steam-shared/upper \
             ~/.local/share/steam-shared/work \
             /opt/steam/steamapps/compatdata \
    -- steam
```

Inside the namespace, any write to `/opt/steam/steamapps/compatdata/` goes to the per-user upper layer. The shared lower layer is read-only from the overlay's perspective. Game files outside `compatdata/` are not overlaid — they're shared normally.

## Prior Art

This project originally used a Proton compatibility tool wrapper to redirect `STEAM_COMPAT_DATA_PATH`. That approach was brittle:
- Required selecting the wrapper as the compatibility tool for every game
- Per-game Proton overrides bypassed the wrapper entirely
- Steam sometimes wrote to the original path before the wrapper ran

The bwrap overlay approach solves all of these by operating at the filesystem level, below Steam and Proton.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "add README documenting bwrap overlay approach"
```

---

### Task 8: Legacy cleanup in dotfiles

**Files:**
- Modify: `~/.syncthing/dotfiles/roles/legacy-cleanup/tasks/main.yml`

Add tasks to remove the old wrapper system (compat tool, login hook, systemd watcher, wrapper source files).

- [ ] **Step 1: Add cleanup tasks to legacy-cleanup role**

Append to the end of `roles/legacy-cleanup/tasks/main.yml`:

```yaml

# --- steam-shared-library: old proton wrapper approach ---

- name: "legacy-cleanup: stop steam-fix-perms watcher"
  become: true
  ansible.builtin.systemd:
    name: steam-fix-perms.path
    state: stopped
    enabled: false
  failed_when: false
  when: ansible_facts['os_family'] != "Darwin"

- name: "legacy-cleanup: remove steam-fix-perms systemd units"
  become: true
  ansible.builtin.file:
    path: "{{ item }}"
    state: absent
  loop:
    - /etc/systemd/system/steam-fix-perms.path
    - /etc/systemd/system/steam-fix-perms.service
    - /usr/local/bin/steam-fix-perms
  when: ansible_facts['os_family'] != "Darwin"

- name: "legacy-cleanup: remove steam shared-lib login hook"
  become: true
  ansible.builtin.file:
    path: /etc/profile.d/steam-shared-lib.sh
    state: absent
  when: ansible_facts['os_family'] != "Darwin"

- name: "legacy-cleanup: remove steam wrapper source"
  become: true
  ansible.builtin.file:
    path: /usr/local/share/proton-shared-lib
    state: absent
  when: ansible_facts['os_family'] != "Darwin"

- name: "legacy-cleanup: remove per-user steam wrappers"
  ansible.builtin.file:
    path: "{{ user_home }}/.steam/steam/compatibilitytools.d/proton-shared-lib"
    state: absent
  when: ansible_facts['os_family'] != "Darwin"

- name: "legacy-cleanup: remove per-user steam wrapper (flatpak path)"
  ansible.builtin.file:
    path: "{{ user_home }}/.local/share/Steam/compatibilitytools.d/proton-shared-lib"
    state: absent
  when: ansible_facts['os_family'] != "Darwin"
```

- [ ] **Step 2: Commit in dotfiles repo**

```bash
cd ~/.syncthing/dotfiles
git add roles/legacy-cleanup/tasks/main.yml
git commit -m "add legacy cleanup for old steam proton wrapper system"
```

---

### Task 9: End-to-end test

- [ ] **Step 1: Run activation on FFCACHY**

```bash
cd /path/to/steam-shared-library
sudo ./scripts/activate.sh
```

Verify:
- steamshare group exists
- `/opt/steam/` has correct permissions (2775, steamshare, ACLs)
- `/usr/local/bin/steam-shared` exists and is executable
- `/usr/local/share/applications/steam-shared.desktop` exists
- Stale compatdata prefixes are cleaned

- [ ] **Step 2: Test launcher as main user**

```bash
# verify detection
steam-shared --help
# should show Steam's help output

# verify overlay is working — launch Steam, install/run a small Proton game
# check that prefix lands in ~/.local/share/steam-shared/upper/<appid>/
ls ~/.local/share/steam-shared/upper/
```

- [ ] **Step 3: Run legacy cleanup via dotfiles**

```bash
cd ~/.syncthing/dotfiles
sudo ./scripts/activate.sh
```

Verify:
- `/etc/systemd/system/steam-fix-perms.path` removed
- `/etc/profile.d/steam-shared-lib.sh` removed
- `/usr/local/share/proton-shared-lib/` removed
- `~/.steam/steam/compatibilitytools.d/proton-shared-lib/` removed

- [ ] **Step 4: Test with a second user (GG-5, GG-6)**

```bash
# create a test user
sudo useradd -m testuser
sudo usermod -aG steamshare testuser

# log in as testuser via GDM, launch Steam
# verify: shared games visible, prefix in testuser's ~/.local/share/steam-shared/upper/
# verify: main user's session still works (concurrent GDM sessions)
```

- [ ] **Step 5: Commit any fixes discovered during testing**

```bash
cd /path/to/steam-shared-library
git add -A
git commit -m "fixes from end-to-end testing"
```

---

### Task 10: Nix flake lock and final commit

- [ ] **Step 1: Generate flake.lock**

```bash
cd /path/to/steam-shared-library
nix flake update
```

- [ ] **Step 2: Test nix run activation**

```bash
sudo nix run .#activate
# should produce the same result as sudo ./scripts/activate.sh
```

- [ ] **Step 3: Final commit**

```bash
git add flake.lock
git commit -m "pin flake dependencies"
```

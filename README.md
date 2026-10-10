# Steam Shared Library

Share one Steam game library across multiple Linux users with fully isolated Proton prefixes.

## The Problem

Steam stores Proton/Wine prefixes (`compatdata`) inside the game library folder. When multiple users share a library, they all write to the same prefix directory, causing:

- `wineserver: pfx is not owned by you`
- `PermissionError: os.chmod`
- `pressure-vessel: Permission denied`

## How It Works

Uses [bubblewrap](https://github.com/containers/bubblewrap) to bind a per-user directory onto `/opt/steam/steamapps/compatdata/`:

- **Game files** (`common/`, `shadercache/`) → shared directly, readable and writable by all group members
- **Proton prefixes** (`compatdata/`) → private per-user directory via bwrap's mount namespace
- **Temporary files** (`/tmp`) → private tmpfs per Steam session; X11 sockets and temporary Xauthority remain accessible

Each user's prefixes live in `~/.local/share/steam-shared/compatdata/`. Shared prefixes are not inherited. Multiple users can be logged in simultaneously (GDM user switching) — each session has its own isolated mount namespace.

Existing overlay state is not imported automatically. Before switching an existing installation, preserve its saves and Wine metadata separately. Old directories remain untouched.

**No compatibility tool selection. No per-game configuration. Works with any Proton variant.**

## Prerequisites

- Linux with unprivileged user namespace support
- `bubblewrap` (`pacman -S bubblewrap` / `apt install bubblewrap`)
- `acl` package for `setfacl` (usually pre-installed)
- Steam (native package or Flatpak)
- Nix (for installation via flake)

## Installation

```bash
# install (requires sudo)
nix run github:felixfoertsch/steam-shared-library
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
3. Create per-user `~/.local/share/steam-shared/compatdata/`
4. Launch Steam inside a bwrap mount namespace with that directory bound onto `compatdata/`

```
bwrap --dev-bind / / \
    --bind ~/.local/share/steam-shared/compatdata \
           /opt/steam/steamapps/compatdata \
    -- steam
```

Inside the namespace, reads and writes to `/opt/steam/steamapps/compatdata/` use only the user's directory. Game files outside `compatdata/` remain shared. This protects Steam's own prefix writes as well as Proton's.

## Caveats

### Do not nest `steam-shared` inside another bwrap wrapper

`bwrap` without the setuid bit (the default on modern distros) creates an **unprivileged user namespace**. User namespaces cannot preserve supplementary groups — every group except the primary one becomes `nobody` inside the namespace.

That has two consequences if you wrap `steam-shared` inside an outer bwrap (for example, a Steam lancache wrapper that bind-mounts a custom `resolv.conf`):

1. The `steamshare` group check in `steam-shared` fails — `id -nG` no longer lists `steamshare` inside the outer namespace.
2. Even if you bypass the check, Steam itself cannot write to `/opt/steam/steamapps/common/`. The group bit that grants access is gone inside the namespace, so new game installs fail with `EACCES`.

If you need a lancache or similar DNS redirect, put it at the **system level** (a `systemd-resolved` drop-in, or a local `dnsmasq`), not inside a second bwrap around `steam-shared`.

## Prior Art

This project originally used a Proton compatibility tool wrapper to redirect `STEAM_COMPAT_DATA_PATH`. That approach was brittle:
- Required selecting the wrapper as the compatibility tool for every game
- Per-game Proton overrides bypassed the wrapper entirely
- Steam sometimes wrote to the original path before the wrapper ran

Filesystem-level bwrap isolation solves all of these, below Steam and Proton. Earlier versions used an overlay with shared prefixes as its lower layer. Inherited root-owned files could fail during Proton updates inside an unprivileged user namespace (`OSError: [Errno 75] Value too large for defined data type`). Binding fully user-owned prefixes avoids that inheritance while keeping game files shared.

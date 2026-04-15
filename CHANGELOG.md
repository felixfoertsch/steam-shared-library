# Changelog

All notable changes are documented in this file.

## 2026.04.15

### Added
- Bubblewrap-based Steam launcher with per-user `compatdata` overlay isolation.
- Activation, uninstall, and add-user helper scripts.
- Desktop launcher override routing Steam startup through `steam-shared`.
- Permission repair watcher (`steam-fix-perms.path` + `steam-fix-perms.service`).
- Nix flake packages for `activate`, `uninstall`, and `add-user`.
- Basic shell test harness for preflight behavior and release guard checks.

### Changed
- Activation output now reports the correct desktop file path: `/usr/local/share/applications/steam.desktop`.

### Notes
- First public product release.
- Linux-only.

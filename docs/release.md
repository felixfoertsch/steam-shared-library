# Release Guide

This guide defines the repeatable release procedure for GitHub product releases.

## Preflight

Run all checks locally from the repository root:

```bash
shellcheck scripts/*.sh tests/*.sh
bash -n scripts/*.sh tests/*.sh
desktop-file-validate desktop/steam.desktop
tests/run.sh
XDG_CACHE_HOME=/tmp nix flake check --no-build --no-write-lock-file
```

## Versioning

Use CalVer tags: `YYYY.MM.DD`.
If multiple releases happen on the same day, append `.1`, `.2`, and so on.

## Release Steps

1. Update `CHANGELOG.md` with the exact release version and notes.
2. Push all release files to `main`.
3. Create an annotated tag.
4. Push the tag.
5. Create a GitHub Release from that tag and copy release notes from `CHANGELOG.md`.

Example:

```bash
git tag -a 2026.04.15 -m "release 2026.04.15"
git push origin 2026.04.15
```

## Rollback

1. Revert the problematic commit range on `main`.
2. Cut a new patch release tag for the rollback build (for example `2026.04.15.1`).
3. If a system needs cleanup after failed deployment, run:

```bash
nix run .#uninstall
```

Then re-activate with the corrected release once available.

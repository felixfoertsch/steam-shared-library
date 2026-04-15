# Contributing

## Development Workflow

1. Create a branch from `main`.
2. Implement a focused change.
3. Run local verification.
4. Open a pull request.

## Required Local Checks

```bash
shellcheck scripts/*.sh tests/*.sh
bash -n scripts/*.sh tests/*.sh
desktop-file-validate desktop/steam.desktop
tests/run.sh
XDG_CACHE_HOME=/tmp nix flake check --no-build --no-write-lock-file
```

## Scope Rules

- Keep changes minimal and focused.
- Add or update tests for behavior changes.
- Do not commit secrets.

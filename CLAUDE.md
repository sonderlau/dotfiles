# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A macOS dotfiles repository. A bash script (`sync`) copies local config files into this repo using `rsync`.

## Key Commands

```sh
# Run sync (shows tree preview, asks for confirmation before executing)
./sync
```

## Config Format (`dotfiles.conf`)

```text
# Absolute paths (~ expanded), one per line
# Indented lines starting with ! are exclude patterns

~/.zshrc

~/.config/nvim
  !.git
  !.DS_Store
  !lazy-lock.json
```

Destination is derived automatically: `$HOME/` prefix stripped → `~/.config/nvim` becomes `.config/nvim` in the repo. Non-home paths have leading `/` stripped.

## Conventions

- `Commands.sh` contains one-time macOS `defaults write` commands (run manually after fresh install, not sourced).
- Synced files are copies; edit the originals at `~` and re-run `./sync`.

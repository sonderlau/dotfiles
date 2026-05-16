# dotfiles

My macOS configuration, synced into version control.

## Usage

```sh
./sync
```

Every run shows a tree preview of the resulting repo, then asks for confirmation before syncing. Incremental — only changed files are copied.

## Config

Edit `dotfiles.conf`:

```text
# Absolute paths (~ expanded), one per line
# Indented lines starting with ! are exclude patterns

~/.zshrc

~/.config/nvim
  !.git
  !.DS_Store
  !lazy-lock.json

~/.config/karabiner
  !automatic_backups
```

Destination is derived automatically by stripping the `$HOME/` prefix.
For directories, `rsync --delete` keeps the repo copy in sync — removed source files get cleaned up.

## macOS setup

`Commands.sh` has one-time `defaults write` commands for keyboard repeat rate, hidden files, etc. Run manually after a fresh install.

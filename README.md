# dotfiles

macOS configuration and local automation source backups.

```sh
./sync             # preview, then confirm
./sync --yes       # one-command backup
./sync --dry-run   # preview only
```

The script stages everything first, including sanitized Clash Party exports. Only
that staged content is copied into the repository. Missing sources are skipped.
For directories, `rsync --delete` removes obsolete files within that entry's target.
A cancelled preview or failed export leaves repository backups unchanged.
Source directories that are currently absent leave existing backups in place.

Requirements: Bash, rsync, Python 3, and PyYAML (`python3 -m pip install PyYAML`
if missing). eza is optional; without it the preview uses a file listing.

## Backup list

Edit `dotfiles.conf`. Paths expand `~`; indented `!` lines are rsync exclusions.
Destination defaults to the source path with the home prefix stripped. An explicit
mapping places selected installed-package source outside its dependency directory:

```text
~/.zshrc

~/my project => backups/my-project
  !secrets
  !tmp
```

A custom list can be supplied as `./sync --yes /path/to/list.conf`.
Global exclusions cover `.git`, `node_modules`, `.DS_Store`, Python caches/virtual
environments, `.esphome`, common image formats, and `.drawio` designs. Lockfiles
remain included. Secrets exclusions are explicit in the project entries; do not
add an application data directory wholesale if it contains credentials.

| Source | Repository copy |
| --- | --- |
| Local pi Ghostty status plugin | `.pi/agent/extensions/ghostty-status/` |
| Modified pi-coder plan mode | `backups/pi-coder/extensions/plan-mode/` |
| Shared plan mode sandbox state | `backups/pi-coder/extensions/bash-command-collapse/sandbox-mode.ts` |
| Modified pi question editor | `backups/pi-coder/extensions/ask-user-question/` |
| Installed pi-coder version/dependency metadata | `backups/pi-coder/package.json` |
| Karabiner mappings | `.config/karabiner/` |
| Clash Party sanitized settings | `backups/clash-party/` |
| Home Assistant / ESPHome source | `Dev/home-assistant/` |

Home Assistant keeps firmware configuration, HA packages, and dashboards.
`docs/` designs, images, `tmp/`, `.esphome/`, local secret directories,
`secrets.yaml`, environment files, and databases are excluded.
Pi credentials, models, session histories and the entire npm installation are
outside the backup list. OpenCode `.bak` files are excluded. Literal API keys and
other credential fields in its staged JSON are replaced with `REDACTED` by
`scripts/redact-json-credentials.py`; environment references remain intact.
Live OpenCode files are unchanged. Restore the credentials locally or use an
environment reference before using the restored configuration.

## Clash Party export

`scripts/export-clash-party.py` handles `~/Library/Application Support/mihomo-party`.
It exports software/UI settings, reviewed core settings (ports, DNS, TUN, sniffer),
YAML overrides, and a separate `substore-structure.json` with anonymous subscription
names, ordered collection membership, and allowed Quick Setting Operator values.
The structure file is a reference for rebuilding aggregation, not a replacement
for the original Sub-Store database.

Raw `profile.yaml`, downloaded profiles, subscription URLs, node credentials,
gist keys, Sub-Store tokens/scripts/caches/archives, traffic databases, browser
storage and logs are excluded. Only reviewed public rule/update resources and
ordinary public DNS endpoints are allowed as URLs. Unknown configuration fields
and Sub-Store processors are omitted; custom script overrides are omitted.
Subscriptions and credentials must be added locally after restoring.

The two campus-network helper scripts are copied only while their SHA-256 matches
the reviewed versions in `REVIEWED_SCRIPTS`. If a helper changes, inspect its
contents for credentials and update the hash before running the backup again.
A malformed configuration or changed helper aborts the export and sync.
The application’s original files are never rewritten.

## Restore local pi modifications

The installed pi-coder package version is recorded in `backups/pi-coder/package.json`
(currently 2.5.0). Install that package version and its dependencies first, then
copy these backed-up files into the corresponding installed package paths:

```sh
rsync -a backups/pi-coder/extensions/plan-mode/ \
  ~/.pi/agent/npm/node_modules/@bachi/pi-coder/extensions/plan-mode/
rsync -a backups/pi-coder/extensions/ask-user-question/ \
  ~/.pi/agent/npm/node_modules/@bachi/pi-coder/extensions/ask-user-question/
cp backups/pi-coder/extensions/bash-command-collapse/sandbox-mode.ts \
  ~/.pi/agent/npm/node_modules/@bachi/pi-coder/extensions/bash-command-collapse/sandbox-mode.ts
mkdir -p ~/.pi/agent/extensions/ghostty-status
rsync -a .pi/agent/extensions/ghostty-status/ ~/.pi/agent/extensions/ghostty-status/
```

Restart pi after restoring. These are source snapshots, not a standalone pi-coder
package. Keep the installed package’s other extensions and dependencies. Package
upgrades can overwrite the modifications; review compatibility before restoring
them onto another version. Avoid loading a second copy of plan-mode as a separate
local extension.

## Right Command input-source fix

The pi session on 2026-10-07 in `~/Dev/clashparty` recorded replacing the Karabiner
`right_command → language` (Globe key) mapping with direct input-source selection.
The current `.config/karabiner/karabiner.json` still contains that fix:

- When the source is `im.rime.inputmethod.Squirrel.Hans`, a standalone Right Command
  tap selects `com.apple.keylayout.ABC`.
- Otherwise it selects Squirrel Simplified Chinese.
- `to_if_alone` switches on release; `lazy: true` preserves Command combinations.
- Caps Lock remains mapped to Escape. Karabiner is still required for these rules.

The historical diagnosis attributed the delay to the Globe key’s tap/hold handling
and its interaction with terminal keyboard reporting. This backup task confirmed
the rule and session record; it did not remeasure latency.

The same session fixed the question editor’s IME candidate popup position by
forwarding editor focus/hardware-cursor positioning in `ask-user-question/view.ts`.
That installed-package modification is included above. Full session logs are not
backed up.

For Home Assistant restoration, recreate `esphome/secrets.yaml` locally with the
keys referenced by `!secret` in `waveshare.yaml`, and recreate any local HA access
environment files. The firmware/automation source alone does not include them.

## Verification

```sh
bash -n sync
python3 -m unittest discover -s tests -v
./sync --dry-run
```

The tests use temporary homes and repositories to check exclusions, confirmation,
path mappings, scoped deletion, and removal of synthetic credentials/URLs.

## macOS setup

`Commands.sh` contains one-time macOS defaults commands for manual setup.

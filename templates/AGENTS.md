# Agent prompt: rebuild this Omarchy machine

You are an agent (Claude Code, Codex, Pi, …). Your job is to make **this device** match the machine described in this repo: software, apps and configuration. Work in order, verify every step, and finish with a report of what is done, what failed, and what the user must do by hand.

This repo holds only configuration and instructions. It is written by the backup tool `omarchy-sync`: https://github.com/jlopezlira/omarchy-backup

## Rules
- First run `uname -m`, `cat /etc/os-release` and `omarchy version`. If this is not Omarchy/Arch, say so and stop.
- Ask before any `sudo` command. Never write passwords or tokens into this repo.
- `omarchy-sync setup` keeps existing files as `*.pre-dotfiles`; do not overwrite anything else without a backup.
- Paths may contain the original user's home: adapt them to the real `$HOME`.
- Anything you cannot verify (download URLs, versions) must come from the official source. **Never invent URLs.**
- Secrets are not in this repo (sign-ins, tokens, cookies). Ask the user to sign in again.

## New machine
1. Clone the tool: `git clone https://github.com/jlopezlira/omarchy-backup ~/Projects/omarchy-backup`.
2. Run `~/Projects/omarchy-backup/bin/omarchy-sync restore-github`. It signs in to GitHub, asks which repo and **which backup** to restore (the user must choose), clones it, and runs `setup`.
3. `setup` installs the packages in `pkgs/`, copies `home/` into `$HOME`, installs `mise` tools, enables services, loads dconf, installs herdr integrations, and installs the backup timer and bar plugin.
4. Read `INVENTORY.md`. For each row of *Software installed outside pacman*: follow `apps/<id>.md` if it exists. If Doc is `—`, find the official install method for this architecture, install it, verify it, and create `apps/<id>.md` (first line `ids: <id> [other ids]`, then what it is, where it comes from, how to install and verify it, and which data is not backed up).
5. Check `pkgs/services-system.txt` (system services to enable) and `pkgs/etc-modified.txt` (changed `/etc` files, reference only: ask the user).
6. Add the bar widget: `omarchy bar put jj.backup-status --section right`.
7. Final check (run and report): `omarchy-sync status`, `hyprctl configerrors`, `mise ls`.

## Restore a backup on an existing machine
- `omarchy-sync log 20` lists backups; `omarchy-sync restore <hash> --dry-run` previews; `omarchy-sync restore <hash>` restores.
- The current setup is committed first as `snapshot: before restoring <hash>`, so a restore can be undone.
- Missing packages from that backup: `omarchy-sync restore-packages` (sudo).

## Several machines

All machines share this repo and must end up configured the same (theme, agents, packages, plugins), except work files and per-machine files (`hypr/monitors.lua`, `omarchy/shell.toml`, the sync config). When `omarchy-sync status --json` shows `incoming`, another machine saved new configuration: ask the user **about each change** (`status --json` lists them under `incoming.files` and `incoming.extras`; `incoming.both` names the files this machine changed too), then run `omarchy-sync apply <file|theme|packages|plugins|claude-prefs|software>...` / `omarchy-sync skip <item>...` for what they chose, or `apply` / `skip` with no items for everything. A declined item is not asked about again until the other machine changes it; this machine's version is backed up instead, so the other machine gets asked in turn. On a file changed on both machines the other machine's copy wins (this machine's is kept in `~/.local/state/omarchy-sync/conflicts/`). `apply` also installs the other machine's packages, pnpm tools, herdr integrations, Claude plugins and preferences, and replicates its removals (files marked `deleted`, packages under the `removals` item) when they are accepted. Never write secrets into this repo: values shown as `REDACTED` are removed on purpose, `apply` fills them from this machine's own copy when it has one, and the user fills in the rest.

## Maintenance
- `omarchy-sync interval <15min|30min|1h|6h|12h|24h|off>` sets the schedule. Runs commit only when something changed.
- When a new app is installed outside pacman, `omarchy-sync status` flags it as undocumented: describe it in `apps/<id>.md`.
- To back up a new config path, add it to `sync.list`.

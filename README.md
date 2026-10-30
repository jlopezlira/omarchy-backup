# omarchy-backup

Back up an [Omarchy](https://omarchy.org) machine (configuration and the list of installed software) into a **separate private git repo**, on a schedule, and restore it.

The backup repo holds only configuration and instructions: dotfiles, package lists, a machine inventory, and an `AGENTS.md` guide that coding agents follow to rebuild the machine. This repo holds the tool:

- `bin/omarchy-sync`: the CLI.
- `systemd/`: the user service and timer.
- `plugin/jj.backup-status/`: an Omarchy bar widget with status, schedule, the last 5 backups, and one-click restore.

## Install

```bash
git clone https://github.com/jlopezlira/omarchy-backup ~/Projects/omarchy-backup
~/Projects/omarchy-backup/bin/omarchy-sync init          # choose where backups go
omarchy bar put jj.backup-status --section right
```

`init` asks for a folder (default `~/omarchy-sync`) and where to push it:

1. a new **private GitHub repo** (uses `gh`, so run `gh auth login` first),
2. an **existing git remote** (any URL; if it already holds a backup, it is reused),
3. **nowhere**, keeping backups on this machine only.

It creates the repo from `templates/` (`sync.list`, `AGENTS.md`, `.gitignore`), saves the location as `REPO=` in `~/.config/omarchy-sync/config`, installs the timer and the bar plugin, and makes the first backup. Without a terminal, pass the answers as flags: `omarchy-sync init ~/omarchy-sync --github my-backup` (or `--remote <url>`, or `--local`). The bar widget shows a **Set up backup** button until a location exists.

To move backups somewhere else later, run `init` again with the new path, or edit `REPO=`.

**New machine:** install Omarchy, then:

```bash
git clone https://github.com/jlopezlira/omarchy-backup ~/Projects/omarchy-backup
~/Projects/omarchy-backup/bin/omarchy-sync restore-github
```

It installs `gh` if needed, signs you in to GitHub in the browser, lists your private repos to pick the backup repo, clones it, and shows the machines it holds and the last 20 backups, each with the machine it came from, so you choose which one to apply. Each backup is named `backup: <date> · <host> · <apps that changed>`, its commit body lists every file, and a `Machine: <host>` trailer records where it was made (older backups fall back to the host in their `INVENTORY.md`). Then it runs `setup` (packages, files, tools, services, theme, this tool and the bar widget). If the widget is already installed, its first-run panel has a **Restore from GitHub** button that does the same. Finally follow the backup repo's `AGENTS.md`.

## Updates

Each `run` (the timer too) first pulls this tool's repo. When it moved, it reinstalls the bar plugin and the units and carries on with the new script, so every machine picks up fixes on its next backup. A clone with local edits is never pulled. The plugin is not part of the backups, so restoring an old backup cannot bring back an old plugin.

## Usage

```
omarchy-sync init [path] [--github NAME | --remote URL | --local]
omarchy-sync run                       back up now (commits and pushes only when something changed)
omarchy-sync status [--json]           state, schedule, and the last 5 backups
omarchy-sync log [N] [machine]         last N backups, with the machine each came from
omarchy-sync machines                  machines in the backup repo and their latest backup
omarchy-sync interval <15min|30min|1h|6h|12h|24h|off>
omarchy-sync restore <rev|machine> [--dry-run]  restore files from a backup, or a machine's latest one
                                       (the current setup is snapshotted first; this machine keeps its own REPO=)
omarchy-sync restore-packages [rev]    install packages a backup had and this machine lacks (sudo)
omarchy-sync setup [repo]              rebuild a new machine from a backup repo
omarchy-sync restore-github [owner/name] [path]  sign in, pick a backup, clone it, setup
omarchy-sync install | uninstall
```

## What gets backed up

The paths listed in the backup repo's `sync.list`, minus secrets and caches (`auth.json`, `hosts.yml`, keyrings, sqlite databases, logs, files over 2 MB). Each run also records pacman/AUR packages, mise/npm/pnpm/uv tools, enabled services, dconf, herdr integrations, and an `INVENTORY.md` that flags software installed outside pacman (AppImages, curl installers) so you can document how to reinstall it under `apps/<id>.md`.

Before every commit a scan blocks anything that looks like a token or private key.

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

It installs `gh` if needed, signs you in to GitHub in the browser, lists your private repos to pick the backup repo, clones it, and shows the last 20 backups so you choose which one to apply. Each backup is named `backup: <date> · <host> · <apps that changed>`, and its commit body lists every file. Then it runs `setup` (packages, files, tools, services, theme, this tool and the bar widget). If the widget is already installed, its first-run panel has a **Restore from GitHub** button that does the same. Finally follow the backup repo's `AGENTS.md`.

## Usage

```
omarchy-sync init [path] [--github NAME | --remote URL | --local]
omarchy-sync run                       back up now (commits and pushes only when something changed)
omarchy-sync status [--json]           state, schedule, and the last 5 backups
omarchy-sync log [N]                   last N backups
omarchy-sync interval <15min|30min|1h|6h|12h|24h|off>
omarchy-sync restore <rev> [--dry-run] restore files from a backup (the current setup is snapshotted first)
omarchy-sync restore-packages [rev]    install packages a backup had and this machine lacks (sudo)
omarchy-sync setup [repo]              rebuild a new machine from a backup repo
omarchy-sync restore-github [owner/name] [path]  sign in, pick a backup, clone it, setup
omarchy-sync install | uninstall
```

## What gets backed up

The paths listed in the backup repo's `sync.list`, minus secrets and caches (`auth.json`, `hosts.yml`, keyrings, sqlite databases, logs, files over 2 MB). Each run also records pacman/AUR packages, mise/npm/pnpm/uv tools, enabled services, dconf, herdr integrations, and an `INVENTORY.md` that flags software installed outside pacman (AppImages, curl installers) so you can document how to reinstall it under `apps/<id>.md`.

Before every commit a scan blocks anything that looks like a token or private key.

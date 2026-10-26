# omarchy-backup

Back up an [Omarchy](https://omarchy.org) machine (configuration and the list of installed software) into a **separate private git repo**, on a schedule, and restore it.

The backup repo holds only configuration and instructions: dotfiles, package lists, a machine inventory, and an `AGENTS.md` guide that coding agents follow to rebuild the machine. This repo holds the tool:

- `bin/omarchy-sync`: the CLI.
- `systemd/`: the user service and timer.
- `plugin/jj.backup-status/`: an Omarchy bar widget with status, schedule, the last 5 backups, and one-click restore.

## Install

```bash
git clone https://github.com/jlopezlira/omarchy-backup ~/Projects/omarchy-backup
~/Projects/omarchy-backup/bin/omarchy-sync install          # timer + bar plugin
omarchy bar put jj.backup-status --section right
```

The backup repo defaults to `~/omarchy-sync`. Set `REPO=` in `~/.config/omarchy-sync/config` to change it. The backup repo must exist and have a remote to push to.

**New machine:** clone your backup repo, then run `omarchy-sync setup <backup-repo>`. It installs packages, copies the files, enables services, and installs this tool. Then follow the backup repo's `AGENTS.md`.

## Usage

```
omarchy-sync run                       back up now (commits and pushes only when something changed)
omarchy-sync status [--json]           state, schedule, and the last 5 backups
omarchy-sync log [N]                   last N backups
omarchy-sync interval <15min|30min|1h|6h|12h|24h|off>
omarchy-sync restore <rev> [--dry-run] restore files from a backup (the current setup is snapshotted first)
omarchy-sync restore-packages [rev]    install packages a backup had and this machine lacks (sudo)
omarchy-sync setup [repo]              rebuild a new machine from a backup repo
omarchy-sync install | uninstall
```

## What gets backed up

The paths listed in the backup repo's `sync.list`, minus secrets and caches (`auth.json`, `hosts.yml`, keyrings, sqlite databases, logs, files over 2 MB). Each run also records pacman/AUR packages, mise/npm/pnpm/uv tools, enabled services, dconf, herdr integrations, and an `INVENTORY.md` that flags software installed outside pacman (AppImages, curl installers) so you can document how to reinstall it under `apps/<id>.md`.

Before every commit a scan blocks anything that looks like a token or private key.

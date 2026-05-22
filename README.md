# [Nightly encrypted offsite backup of $HOME on macOS](https://lucas.zip/macos-restic-b2)

Encrypted, deduplicated, scheduled backups from a personal Mac to Backblaze B2 using [restic](https://restic.net) and [resticprofile](https://creativeprojects.github.io/resticprofile/).

This is the code accompanying the article linked above. This README is just a map of what lives in the repo.

## Layout

```
site.conf.example          per-machine values: copy → site.conf, edit, render
bin/configure.sh           renders bin/*.tmpl + config/*.tmpl from site.conf
bin/schedule-install.sh    idempotent launchd installer (4 agents)
bin/restic-wrap.sh         loads Keychain secrets, execs resticprofile
bin/restic-notify.sh       POSTs run-after / run-after-fail notifications
config/profiles.toml.tmpl  resticprofile retention, locks, hooks, schedule-log targets
config/excludes.txt        backup exclusions
```

`bin/*.tmpl` and `config/*.toml.tmpl` are committed; their rendered outputs are .gitignored.

Notifications are optional. The author's setup posts to a private Telegram gateway; if you fork this, either plug in your own notifier or leave `NOTIFY_ENDPOINT` empty in `site.conf` to disable them entirely.

## Setup

```
cp site.conf.example site.conf
$EDITOR site.conf
bin/configure.sh
bin/schedule-install.sh
```

The repo expects to live at `~/backups`. Don't put it under `~/Documents`, `~/Desktop`, or `~/Downloads` — macOS TCC will block the launchd-spawned `/bin/zsh` from reading scripts there.

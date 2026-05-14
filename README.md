# [Nightly encrypted offsite backup of $HOME on macOS](https://lucas.zip/macos-restic-b2)

Encrypted, deduplicated, scheduled backups from a personal Mac to Backblaze B2 using [restic](https://restic.net) and [resticprofile](https://creativeprojects.github.io/resticprofile/).

This is the code accompanying the article linked above. The article walks through the architecture, the macOS security mechanics (TCC / AMFI / Keychain), and the end-to-end setup. This README is just a map of what lives in the repo.

## Layout

```
site.conf.example         per-machine values: copy → site.conf, edit, render
bin/configure.sh          renders bin/*.tmpl + config/*.tmpl from site.conf
bin/*.tmpl                templates (committed); rendered output is .gitignored
bin/launcher.c            exec stub compiled into each .app bundle
bin/emoji-to-icns.sh      rasterizes an emoji glyph into .icns for bundle icons
bin/test-notify.sh        fixture-driven smoke test for restic-notify.sh
config/profiles.toml.tmpl resticprofile schedules, retention, hooks
config/excludes.txt       backup exclusions
```

Notifications are optional. The author's setup posts to a private Telegram gateway; if you fork this, either plug in your own notifier or leave `NOTIFY_ENDPOINT` empty in `site.conf` to disable them entirely.

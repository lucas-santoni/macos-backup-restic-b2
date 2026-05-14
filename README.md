# backups

Encrypted, deduplicated, scheduled backups from a personal Mac to Backblaze B2 using [restic](https://restic.net) and [resticprofile](https://creativeprojects.github.io/resticprofile/). Notifications are 100% optional — the author wires them to their own Telegram gateway; if you want notifications in your fork, plug in your own notifier (or leave `NOTIFY_ENDPOINT` empty to disable them entirely).

- Secrets in macOS Keychain — never on disk.
- Configuration as code — this repo is everything except the secrets.
- Schedule fires nightly via per-command launchd agents that surface in System Settings → Login Items as four readable rows, one per command, each prefixed with your `BUNDLE_NAME_PREFIX` (e.g. "Laptop Backup", "Laptop Forget", "Laptop Prune", "Laptop Check").

## What's where

```
site.conf.example         per-machine values: copy → site.conf, edit, render
bin/configure.sh          renders bin/*.tmpl + config/*.tmpl from site.conf
bin/*.tmpl                templates (committed); rendered output is .gitignored
bin/launcher.c            Mach-O exec stub compiled into each .app bundle
bin/emoji-to-icns.sh      rasterizes an emoji glyph into .icns for bundle icons
bin/test-notify.sh        fixture-driven smoke test for restic-notify.sh
config/profiles.toml.tmpl resticprofile schedules, retention, hooks
config/excludes.txt       backup exclusions
```

The repo ships templates with `{{PLACEHOLDER}}` markers for the five values that are personal to a machine: `USERNAME`, `B2_REPO`, `BUNDLE_ID_PREFIX`, `BUNDLE_NAME_PREFIX`, `NOTIFY_ENDPOINT`. `bin/configure.sh` reads `site.conf` and renders the templates into runnable scripts (gitignored). Runtime scripts (`bin/restic-wrap.sh`, plus `bin/restic-notify.sh` when notifications are enabled) stay in the repo and are invoked from there. The launchd-spawned chain rooted at a signed bundle propagates Full Disk Access via TCC's responsible-process attribution, so reads from `~/Documents/` work without any deploy step.

## Setup on a new Mac

Apple Silicon, macOS Sonoma or later. Steps are ordered — earlier ones are prerequisites for later ones. `bin/install-bundles.sh.tmpl` compiles `bin/launcher.c` with `-arch arm64`; on Intel, edit the template to `-arch x86_64` (or pass both for a universal build) before running `configure.sh`.

### 0. External prerequisites (web UIs, one-time)

These produce the values you'll plug into `site.conf` in step 1, and the keys you'll store in Keychain in step 4.

- **Backblaze B2.** Create a private bucket (no Object Lock, lifecycle = Keep all versions). Create an application key scoped to that bucket with read+write. Save the key ID and key secret — you'll paste them into Keychain in step 4.
- **Notification gateway** (optional). The setup POSTs a JSON payload to the URL in `NOTIFY_ENDPOINT` — designed for a small gateway that proxies to Telegram, but the payload shape is generic. Stand up your own gateway, or swap the URL/auth in `bin/restic-notify.sh` for whatever notifier you prefer. To disable notifications entirely, leave `NOTIFY_ENDPOINT=""` in `site.conf`: `configure.sh` will skip rendering `bin/restic-notify.sh` and strip the `run-after` / `run-after-fail` hooks from `profiles.toml`. Skip step 4's `telegram-gateway-api-key` Keychain entry in that case.

### 1. Configure for this machine

```sh
cp site.conf.example site.conf
$EDITOR site.conf      # uncomment / fill in the values
bin/configure.sh       # renders bin/*.tmpl + config/profiles.toml.tmpl
```

After this, `bin/restic-wrap.sh`, `bin/schedule-install.sh`, `bin/install-bundles.sh`, and `config/profiles.toml` exist as runnable files (gitignored, regenerated on demand); `bin/restic-notify.sh` is also rendered when `NOTIFY_ENDPOINT` is non-empty. Re-run `configure.sh` after editing `site.conf` or pulling updated templates.

### 2. Install dependencies

```sh
# Homebrew (skip if already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# restic + resticprofile
brew install restic
brew tap creativeprojects/tap
brew install creativeprojects/tap/resticprofile
```

### 3. Grant Full Disk Access (System Settings, GUI-only)

System Settings → Privacy & Security → Full Disk Access → toggle ON for both:

- `/opt/homebrew/bin/restic`
- `/opt/homebrew/bin/resticprofile`

You'll need to add them via the `+` button (use ⌘⇧G to paste the path). Without FDA, restic can't read most of your home directory.

This step **cannot be scripted** — TCC consent has to come through System Settings.

### 4. Create the Keychain entries

Each entry is a generic password under your `USERNAME` from `site.conf`. The `read -s` form keeps the password out of shell history; passing `-w "$VAR"` after avoids a different gotcha where omitting `-w` silently stores an empty entry.

```sh
source site.conf

# Repo password — generate with `openssl rand -base64 32` and ALSO save in
# your password manager. If lost, the backup is permanently inaccessible.
read -rs "?Repo password: " PW && security add-generic-password -a "$USERNAME" -s restic-repo-password     -w "$PW" -T "" -U && unset PW

read -rs "?B2 keyID: "      PW && security add-generic-password -a "$USERNAME" -s restic-b2-key-id         -w "$PW" -T "" -U && unset PW
read -rs "?B2 appKey: "     PW && security add-generic-password -a "$USERNAME" -s restic-b2-app-key        -w "$PW" -T "" -U && unset PW

# Skip if NOTIFY_ENDPOINT is empty in site.conf (notifications disabled).
read -rs "?Notify key: "    PW && security add-generic-password -a "$USERNAME" -s telegram-gateway-api-key -w "$PW" -T "" -U && unset PW
```

Verify the repo password round-trips (`wc -c` should print ~45 — 44 bytes of base64 from `openssl rand -base64 32`, plus the trailing newline `security` appends):

```sh
security find-generic-password -a "$USERNAME" -s restic-repo-password -w | wc -c
```

The other three entries (B2 keyID, B2 appKey, notify key) carry whatever shape the issuing service assigned, so there's no canonical length to check against.

### 5. Initialize the repo (first time only)

```sh
~/Documents/backups/bin/restic-wrap.sh -n default init
```

This creates the repo on B2 with the password you stored. Skip if you're connecting to an existing repo that someone else already initialized — the wrapper will use it as-is.

### 6. Build the bundles and install the schedules

```sh
~/Documents/backups/bin/install-bundles.sh    # builds + signs the four <BUNDLE_NAME_PREFIX> <Cmd>.app launchd wrappers
~/Documents/backups/bin/schedule-install.sh   # generates launchd plists, patches them, bootstraps into gui/<uid>
```

Order matters: bundles → schedules.

### 7. Grant Full Disk Access to the four bundles (System Settings, GUI-only)

System Settings → Privacy & Security → Full Disk Access → `+` → use ⌘⇧G and paste:

```
~/Documents/backups/bundles
```

Multi-select all four `<BUNDLE_NAME_PREFIX> <Cmd>.app` bundles and click Open. They'll appear as four toggled-on rows.

Why this is necessary even though `restic` already has FDA: TCC keys consent on the *responsible process* at the top of the launchd-spawned exec chain — that's the bundle's launcher binary, not the deeply nested `restic`. Without bundle FDA, you'd get repeated per-folder popups (Documents / Photos / Desktop / etc.) on every fresh consent state. Bundle FDA short-circuits this entirely.

**If you ever re-run `bin/install-bundles.sh`**, the bundles get a new cdhash and the existing FDA grants stop applying. Remove and re-add the four bundles in System Settings.

### 8. Approve Login Items (System Settings, GUI-only)

System Settings → General → Login Items & Extensions → "App Background Activity" section. Each "<BUNDLE_NAME_PREFIX> ..." row should be toggled on. macOS may show a one-time consent prompt — accept.

### 9. Verify

Smoke-test the notification rendering. The dry-run below exercises 9 scenarios spanning the three severity levels (4 info, 1 warning, 4 error) and prints each JSON payload to stdout without POSTing:

```sh
RESTIC_NOTIFY_DRY_RUN=1 ~/Documents/backups/bin/test-notify.sh
```

Drop `RESTIC_NOTIFY_DRY_RUN=1` to actually fire all 9 through the gateway (real Telegram messages, ~3 seconds total).

> ⚠️ This step requires notifications enabled — `bin/restic-notify.sh` doesn't exist when `NOTIFY_ENDPOINT` is empty. The fixtures inside `bin/test-notify.sh` also hardcode the author's username and hostname into the synthetic log text; for any other usage, adapt them to match your environment before running.

Kickstart each agent manually instead of waiting for 02:30:

```sh
source site.conf
for cmd in backup forget check prune; do
  launchctl kickstart -p "gui/$(id -u)/$BUNDLE_ID_PREFIX.$cmd"
done
```

Use `kickstart` specifically — running `restic-wrap.sh` directly from your terminal goes through Terminal.app as the responsible process (which already has its own consent state) and won't faithfully reproduce the launchd-spawned permission landscape that fires at 02:30.

Restore drill (mandatory — a backup you've never restored isn't a backup):

```sh
F="$HOME/.zshrc"   # any small file you can verify byte-for-byte
mkdir -p /tmp/restore-test
~/Documents/backups/bin/restic-wrap.sh -n default restore latest \
  --target /tmp/restore-test \
  --include "$F"
diff "$F" "/tmp/restore-test$F"
```

If `diff` is empty, you're done.

## Adjustments

All per-machine values live in `site.conf`. Four are required; `NOTIFY_ENDPOINT` is optional (leave empty to disable notifications):

| Variable | What it does | Example |
|---|---|---|
| `USERNAME` | macOS short username — Keychain account + path component | `alex` |
| `B2_REPO` | Backblaze B2 repository URL | `b2:my-bucket:/mbp` |
| `BUNDLE_ID_PREFIX` | Reverse-DNS prefix for the four launchd bundles | `com.you.backups` |
| `BUNDLE_NAME_PREFIX` | Display name prefix in System Settings → Login Items | `Laptop` |
| `NOTIFY_ENDPOINT` | URL that receives the notification POST (optional) | `https://notify.example.com/hook` |

The hostname isn't a `site.conf` value — when notifications are enabled, `bin/restic-notify.sh` reads it at runtime via `socket.gethostname()` to tag each payload.

## Day-to-day

- Logs: `~/Documents/backups/logs/{backup,forget,prune,check}.log` for resticprofile output, `launchd-<job>.{out,err}.log` for launchd-level capture.
- One-off restic command: `~/Documents/backups/bin/restic-wrap.sh -n default <command>` (e.g. `snapshots`, `stats`, `find -h`).
- Editing a runtime script: edit `bin/restic-wrap.sh.tmpl` (and `bin/restic-notify.sh.tmpl` if notifications are enabled) in this repo, then re-run `bin/configure.sh` to render. No deploy step — launchd jobs read directly from the repo.
- Re-installing schedules after a config change: `bin/schedule-install.sh` is idempotent.

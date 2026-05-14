#!/bin/zsh
# Exercise restic-notify.sh against fixture log sections so each rendering
# path (info / warning / error, across backup / forget / prune / check) can
# be verified without waiting for a real run.
#
# Each scenario writes a synthetic per-command log to a tmp dir, then
# invokes restic-notify.sh in dry-run mode (RESTIC_NOTIFY_DRY_RUN=1 prints
# the JSON payload to stdout instead of POSTing). Re-run any time the
# parsing logic or notification shape changes.
#
# The fixtures are deliberately rough imitations of real restic output —
# enough lines to satisfy each command's regex, no more.
#
# ⚠️ HEAVILY MACHINE-SPECIFIC. The fixture lines below hardcode the author's
# username (`/Users/lucas/...`) and hostname (`Hercules`) directly into the
# synthetic log text — they aren't rendered through site.conf templating.
# For any usage other than the author's, edit the fixture strings to match
# your own paths and hostname before running.

set -euo pipefail

NOTIFY="$HOME/Documents/backups/bin/restic-notify.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixture log writers — one per command. Each starts with the
# "starting '<command>'" marker the notify-script parser uses to scope to
# the most recent run.

write_backup_success() {
  cat > "$TMP/backup.log" <<'LOG'
2026/05/01 02:30:00 INFO  profile 'default': starting 'backup'
using parent snapshot fc468d65
processed 39888 files, 12.694 GiB in 0:23
Added to the repository: 764.292 MiB (428.652 MiB stored)
snapshot 6a4f9be1 saved
LOG
}

write_backup_warning() {
  cat > "$TMP/backup.log" <<'LOG'
2026/05/01 02:30:00 INFO  profile 'default': starting 'backup'
error: open /Users/lucas/Library/.../milo.db-wal: operation not permitted
processed 39539 files, 12.460 GiB in 3:21
Added to the repository: 271.442 MiB (200.367 MiB stored)
snapshot 4f59f638 saved
LOG
}

write_forget() {
  cat > "$TMP/forget.log" <<'LOG'
2026/05/01 03:00:00 INFO  profile 'default': starting 'forget'
Applying Policy: keep 30 daily, 9999 monthly snapshots
keep 270 snapshots:
ID        Time                 Host         Tags
abcd1234  2026-05-01 02:30:00  Hercules     scheduled
270 snapshots

remove 5 snapshots:
ID        Time                 Host         Tags
deadbeef  2026-04-01 02:30:00  Hercules     scheduled
5 snapshots
LOG
}

write_prune() {
  cat > "$TMP/prune.log" <<'LOG'
2026/05/05 04:00:00 INFO  profile 'default': starting 'prune'
to delete:           1234 blobs / 312.5 MiB
total prune:         1321 blobs / 324.544 MiB
remaining:          18762 blobs / 8.213 GiB
LOG
}

write_check() {
  cat > "$TMP/check.log" <<'LOG'
2026/05/05 05:00:00 INFO  profile 'default': starting 'check'
load indexes
check all packs
read 5% of the data packs
no errors were found
LOG
}

run() {
  local label="$1" cmd="$2" outcome="$3" exit_code="${4:-}" err_msg="${5:-}"
  echo
  echo "── $label ──"
  RESTIC_NOTIFY_DRY_RUN=1 RESTIC_NOTIFY_LOG_DIR="$TMP" \
    PROFILE_NAME="default" PROFILE_COMMAND="$cmd" \
    ERROR_EXIT_CODE="$exit_code" ERROR_MESSAGE="$err_msg" \
    "$NOTIFY" "$outcome"
}

echo "Fixtures in: $TMP"

# Success path for each command.
write_backup_success
run "info: backup succeeded" backup success

write_forget
run "info: forget (270 kept · 5 removed)" forget success

write_prune
run "info: prune" prune success

write_check
run "info: check" check success

# Warning path — backup completed but some files unreadable (exit 3).
write_backup_warning
run "warning: backup exit 3" backup failure 3 "snapshot saved but some files were unreadable"

# Error paths.
write_backup_success
run "error: backup repository unreachable" backup failure 1 "Fatal: unable to open repository: backend not reachable"

write_forget
run "error: forget locked" forget failure 11 "forget on profile 'default': exit status 11"

write_prune
run "error: prune corrupt index" prune failure 10 "Fatal: pack file cannot be read: invalid SHA256"

write_check
run "error: check found errors" check failure 10 "check failed: tree is damaged"

echo
echo "Done."

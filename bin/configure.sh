#!/bin/zsh
# Render bin/*.tmpl and config/*.tmpl into runnable scripts/configs using
# values from site.conf at the repo root.
#
# Run this:
#   - once after cloning, before any of the install scripts;
#   - again any time site.conf is edited;
#   - again after a `git pull` that changes any .tmpl file.
#
# Rendered output paths are .gitignored — they're regenerated from templates.

set -euo pipefail

REPO="$HOME/Documents/backups"
CONF="$REPO/site.conf"
EX="$REPO/site.conf.example"

if [[ ! -f "$CONF" ]]; then
  echo "site.conf not found at $CONF"
  echo
  echo "Copy the example and edit:"
  echo "  cp '$EX' '$CONF'"
  echo "  \$EDITOR '$CONF'"
  exit 1
fi

source "$CONF"

required=(USERNAME B2_REPO BUNDLE_ID_PREFIX BUNDLE_NAME_PREFIX)
missing=()
for var in "${required[@]}"; do
  if [[ -z "${(P)var:-}" ]]; then
    missing+=("$var")
  fi
done
if (( ${#missing[@]} > 0 )); then
  echo "site.conf is missing values for: ${missing[*]}" >&2
  echo "(uncomment the example value or fill in your own, then re-run)" >&2
  exit 1
fi

# Sanity-check values that have a required shape, before sed silently
# produces broken output.
[[ "$B2_REPO" == b2:* ]] || { echo "B2_REPO must start with 'b2:' (got: $B2_REPO)" >&2; exit 1; }

# NOTIFY_ENDPOINT is optional. Empty value = notifications disabled:
# bin/restic-notify.sh isn't rendered, and the run-after hooks in
# profiles.toml (delimited by # NOTIFY:BEGIN/# NOTIFY:END markers) are
# stripped during rendering.
NOTIFY_ENABLED=0
if [[ -n "${NOTIFY_ENDPOINT:-}" ]]; then
  [[ "$NOTIFY_ENDPOINT" == http* ]] || { echo "NOTIFY_ENDPOINT must be a URL (got: $NOTIFY_ENDPOINT)" >&2; exit 1; }
  NOTIFY_ENABLED=1
fi

# Escape the three characters sed treats specially in a replacement string:
# `\` (escape), `&` (back-reference to matched text), and `|` (our chosen
# substitution delimiter). Without this, a NOTIFY_ENDPOINT URL of the form
# `https://host/path?a=1&b=2` would render with its `&` substituted by the
# matched `{{NOTIFY_ENDPOINT}}` placeholder, corrupting the output.
sed_escape() {
  printf '%s' "$1" | /usr/bin/sed -e 's/[\\|&]/\\&/g'
}
USERNAME_ESC=$(sed_escape "$USERNAME")
B2_REPO_ESC=$(sed_escape "$B2_REPO")
BUNDLE_ID_PREFIX_ESC=$(sed_escape "$BUNDLE_ID_PREFIX")
BUNDLE_NAME_PREFIX_ESC=$(sed_escape "$BUNDLE_NAME_PREFIX")
NOTIFY_ENDPOINT_ESC=$(sed_escape "${NOTIFY_ENDPOINT:-}")

# Each entry: <template>:<output>. Templates contain {{VAR}} placeholders;
# we sed them in. Rendered .sh files keep their executable bit (700,
# matching the source-of-truth permission).
templates=(
  "bin/restic-wrap.sh.tmpl:bin/restic-wrap.sh"
  "bin/schedule-install.sh.tmpl:bin/schedule-install.sh"
  "bin/install-bundles.sh.tmpl:bin/install-bundles.sh"
  "config/profiles.toml.tmpl:config/profiles.toml"
)
if (( NOTIFY_ENABLED )); then
  templates+=("bin/restic-notify.sh.tmpl:bin/restic-notify.sh")
elif [[ -f "$REPO/bin/restic-notify.sh" ]]; then
  # Re-rendering after switching from enabled → disabled would otherwise
  # leave a stale rendered script behind.
  rm -f "$REPO/bin/restic-notify.sh"
  echo "removed (stale): bin/restic-notify.sh"
fi

for entry in "${templates[@]}"; do
  src="$REPO/${entry%%:*}"
  dst="$REPO/${entry##*:}"
  if [[ ! -f "$src" ]]; then
    echo "missing template: $src" >&2
    exit 1
  fi
  /usr/bin/sed \
    -e "s|{{USERNAME}}|${USERNAME_ESC}|g" \
    -e "s|{{B2_REPO}}|${B2_REPO_ESC}|g" \
    -e "s|{{BUNDLE_ID_PREFIX}}|${BUNDLE_ID_PREFIX_ESC}|g" \
    -e "s|{{BUNDLE_NAME_PREFIX}}|${BUNDLE_NAME_PREFIX_ESC}|g" \
    -e "s|{{NOTIFY_ENDPOINT}}|${NOTIFY_ENDPOINT_ESC}|g" \
    "$src" > "$dst"

  # profiles.toml wraps each notify hook block with # NOTIFY:BEGIN/END.
  # Enabled → strip just the marker lines. Disabled → strip the whole block.
  # Two separate `-e` expressions for the strip-markers case so the alternation
  # works on BSD sed (macOS) without needing -E.
  if [[ "$dst" == */profiles.toml ]]; then
    if (( NOTIFY_ENABLED )); then
      /usr/bin/sed -i '' -e '/# NOTIFY:BEGIN/d' -e '/# NOTIFY:END/d' "$dst"
    else
      /usr/bin/sed -i '' -e '/# NOTIFY:BEGIN/,/# NOTIFY:END/d' "$dst"
    fi
  fi

  if [[ "$dst" == *.sh ]]; then
    chmod 700 "$dst"
  fi
  echo "rendered: ${entry##*:}"
done

echo
if (( NOTIFY_ENABLED )); then
  echo "Notifications: enabled (endpoint: $NOTIFY_ENDPOINT)."
else
  echo "Notifications: disabled (NOTIFY_ENDPOINT is empty in site.conf)."
fi
echo "Done. Next: bin/install-bundles.sh, bin/schedule-install.sh."

#!/usr/bin/env bash
# kit-update-check.sh — SessionStart hook
#
# Checks npm for a newer @chris1807/claude-kit and re-runs the installer
# non-interactively when one is available. Must never block claude startup —
# every external call is timeout-bounded and every failure exits 0 silently.
#
# Throttled to once per 24h via a marker file. Reads .claude/.kit-install.json
# for the installed version and the choices to pass to the re-install (db, adoOrg).

set +e  # never propagate failures

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(cd "$HOOK_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$CLAUDE_DIR/.." && pwd)"
MANIFEST="$CLAUDE_DIR/.kit-install.json"
MARKER="$CLAUDE_DIR/.kit-update-check"
LOG="$CLAUDE_DIR/.kit-update.log"

# No manifest = legacy install or global-only; nothing to do.
[ -f "$MANIFEST" ] || exit 0

# Throttle to one check per 24h. A failed check still touches the marker so
# unreachable npm doesn't retry every session.
if [ -f "$MARKER" ]; then
  if command -v stat >/dev/null 2>&1; then
    LAST=$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ "$((NOW - LAST))" -lt 86400 ]; then
      exit 0
    fi
  fi
fi

# Crude JSON extraction (avoids requiring jq).
extract() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$MANIFEST" | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}
INSTALLED=$(extract version)
DB=$(extract db)
ADO_ORG=$(extract adoOrg)

# Fetch latest with a 5s timeout — must never hang. `timeout` isn't on macOS
# by default; perl's alarm() is the most portable fallback.
if command -v timeout >/dev/null 2>&1; then
  LATEST=$(timeout 5 npm view @chris1807/claude-kit version 2>/dev/null)
elif command -v gtimeout >/dev/null 2>&1; then
  LATEST=$(gtimeout 5 npm view @chris1807/claude-kit version 2>/dev/null)
elif command -v perl >/dev/null 2>&1; then
  LATEST=$(perl -e 'alarm 5; exec @ARGV or exit 1' npm view @chris1807/claude-kit version 2>/dev/null)
else
  # No timeout mechanism available — skip rather than risk a hang.
  touch "$MARKER"
  exit 0
fi

touch "$MARKER"

[ -z "$LATEST" ] && exit 0
[ -z "$INSTALLED" ] && exit 0
[ "$LATEST" = "$INSTALLED" ] && exit 0

# Only proceed if LATEST sorts strictly greater than INSTALLED.
NEWER=$(printf '%s\n%s\n' "$INSTALLED" "$LATEST" | sort -V | tail -1)
[ "$NEWER" = "$LATEST" ] || exit 0
[ "$NEWER" = "$INSTALLED" ] && exit 0

echo "claude-kit: updating $INSTALLED → $LATEST..." >&2

ARGS=("@chris1807/claude-kit" "init" "$PROJECT_DIR" "--all")
if [ -n "$DB" ] && [ "$DB" != "null" ]; then
  ARGS+=("--db=$DB")
fi
if [ -n "$ADO_ORG" ] && [ "$ADO_ORG" != "null" ]; then
  ARGS+=("--ado-org=$ADO_ORG")
fi

if npx -y "${ARGS[@]}" >"$LOG" 2>&1; then
  echo "claude-kit: updated to $LATEST (log: $LOG)" >&2
else
  echo "claude-kit: update failed (see $LOG)" >&2
fi

exit 0

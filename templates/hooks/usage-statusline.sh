#!/bin/bash
# Usage Status Line (statusLine command, not a hook)
# Shows Claude plan usage in the status line and saves it for usage-warning.sh,
# which warns once a limit reaches 90%.
#
# Claude Code hands plan usage only to the status line command (the
# `rate_limits` field of its stdin JSON). Hooks never see it, so this script is
# the only feed the warning hook has.
#
# Works across plans because it reads whatever windows Claude Code reports:
#   Pro, Max, Team, Enterprise seats → five_hour, seven_day
#   behind a Claude gateway          → spend_limit (with USD when reported)
#   API key, Bedrock, Vertex         → nothing; the segment is left out
# Unknown window names are shown under their own name, so new limits still
# appear without a kit update.
#
# A project statusLine overrides the user's own in ~/.claude/settings.json.
# When the user has one, this script runs it and appends the usage segment to
# its output instead of replacing it.
#
# Colors: yellow from 15 points below the warn threshold, red with ⚠ at it.
# CLAUDE_KIT_USAGE_WARN_PCT changes the threshold (default 90).

# The JSON goes through an env var because python reads its code from stdin.
# (A heredoc inside "$(...)" breaks on macOS bash 3.2 at the first apostrophe.)
export CLAUDE_KIT_STATUSLINE_INPUT="$(cat)"
exec python3 - <<'PY'
import json, math, os, subprocess, tempfile, time

try:
    WARN = min(100.0, max(1.0, float(os.environ.get('CLAUDE_KIT_USAGE_WARN_PCT') or 90)))
except ValueError:
    WARN = 90.0

LABELS = {'five_hour': '5h', 'seven_day': '7d', 'seven_day_opus': '7d opus',
          'seven_day_sonnet': '7d sonnet', 'spend_limit': 'spend'}
RED, YELLOW, RESET = '\033[1;31m', '\033[33m', '\033[0m'
NUM = (int, float)

raw = os.environ.pop('CLAUDE_KIT_STATUSLINE_INPUT', '')
try:
    data = json.loads(raw)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}


def usage_windows(rate_limits):
    if not isinstance(rate_limits, dict):
        return []
    found = [(k, w) for k, w in rate_limits.items()
             if isinstance(w, dict) and isinstance(w.get('used_percentage'), NUM)]
    order = list(LABELS)
    found.sort(key=lambda kw: order.index(kw[0]) if kw[0] in order else len(order))
    return found


def save(windows):
    # Usage belongs to the account, not the project, so the cache is per user.
    cache_dir = os.path.join(os.environ.get('XDG_CACHE_HOME') or os.path.expanduser('~/.cache'), 'claude-kit')
    path = os.path.join(cache_dir, 'usage.json')
    payload = {'rate_limits': dict(windows), 'updated_at': int(time.time())}
    try:
        with open(path) as f:
            if json.load(f).get('rate_limits') == payload['rate_limits']:
                return
    except Exception:
        pass
    try:
        os.makedirs(cache_dir, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=cache_dir, prefix='.usage-')
        with os.fdopen(fd, 'w') as f:
            json.dump(payload, f)
        os.replace(tmp, path)
    except Exception:
        pass


def segment(key, w):
    pct = w['used_percentage']
    label = LABELS.get(key, key.replace('_', ' '))
    used, limit = w.get('used_usd'), w.get('limit_usd')
    if isinstance(used, NUM) and isinstance(limit, NUM):
        text = '%s $%.0f/$%.0f' % (label, used, limit)
    else:
        text = '%s %d%%' % (label, math.floor(pct))
    if pct >= WARN:
        return '%s⚠ %s%s' % (RED, text, RESET)
    if pct >= WARN - 15:
        return '%s%s%s' % (YELLOW, text, RESET)
    return text


def users_own_statusline():
    # Returns the user's status line output, or None when they have none.
    if os.environ.get('CLAUDE_KIT_STATUSLINE_CHILD'):
        return None
    try:
        with open(os.path.expanduser('~/.claude/settings.json')) as f:
            line = json.load(f).get('statusLine') or {}
    except Exception:
        return None
    cmd = line.get('command') if line.get('type', 'command') == 'command' else None
    if not isinstance(cmd, str) or not cmd.strip() or 'usage-statusline' in cmd:
        return None
    try:
        result = subprocess.run(['bash', '-c', cmd], input=raw, capture_output=True, text=True,
                                timeout=5, env=dict(os.environ, CLAUDE_KIT_STATUSLINE_CHILD='1'))
        return result.stdout.rstrip('\n')
    except Exception:
        return ''


def default_line():
    parts = []
    model = (data.get('model') or {}).get('display_name')
    if model:
        parts.append(model)
    ctx = (data.get('context_window') or {}).get('used_percentage')
    if isinstance(ctx, NUM):
        parts.append('ctx %d%%' % round(ctx))
    return ' · '.join(parts)


windows = usage_windows(data.get('rate_limits'))
if windows:
    save(windows)

own = users_own_statusline()
base = own if own is not None else default_line()
lines = base.split('\n') if base else ['']
usage = ' · '.join(segment(k, w) for k, w in windows)
if usage:
    lines[-1] = '%s · %s' % (lines[-1], usage) if lines[-1].strip() else usage
print('\n'.join(lines))
PY

#!/bin/bash
# Usage Warning Hook (SessionStart, UserPromptSubmit, Stop)
# Warns the user once a Claude plan limit reaches 90%: the 5-hour or weekly
# limit on Pro, Max, Team, and Enterprise seats, or a gateway spend limit.
#
# Reads the usage that usage-statusline.sh saves. Claude Code gives plan usage
# only to the status line, so if the project's statusLine is not the kit's
# (a settings.local.json override, say), there is no data and this stays quiet.
# API-key, Bedrock, and Vertex sessions have no plan limits and never warn.
#
# Warns once per limit window: after a warning for the 5-hour limit, the next
# one comes only after that window resets and fills to 90% again. The warned
# state is per user, so several open sessions share one warning.
#
# Runs on three events so a limit crossed mid-turn is reported when the turn
# ends (Stop), and one crossed in another session is reported on the next
# prompt or session start. Never blocks. The message is shown to the user only;
# it is not added to Claude's context.
#
# CLAUDE_KIT_USAGE_WARN_PCT changes the threshold (default 90).

cat > /dev/null  # hook input is not needed

exec python3 - <<'PY'
import datetime, json, math, os, tempfile, time

try:
    WARN = min(100.0, max(1.0, float(os.environ.get('CLAUDE_KIT_USAGE_WARN_PCT') or 90)))
except ValueError:
    WARN = 90.0

NAMES = {'five_hour': '5-hour limit', 'seven_day': 'weekly limit', 'seven_day_opus': 'weekly Opus limit',
         'seven_day_sonnet': 'weekly Sonnet limit', 'spend_limit': 'spend limit'}
NUM = (int, float)
SAME_WINDOW_SECONDS = 1800  # resets_at can drift a little between responses

cache_dir = os.path.join(os.environ.get('XDG_CACHE_HOME') or os.path.expanduser('~/.cache'), 'claude-kit')
usage_path = os.path.join(cache_dir, 'usage.json')
warned_path = os.path.join(cache_dir, 'usage-warned.json')


def load(path):
    try:
        with open(path) as f:
            value = json.load(f)
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def resets_text(ts, now):
    when = datetime.datetime.fromtimestamp(ts)
    clock = when.strftime('%I:%M %p').lstrip('0')
    days_out = (when.date() - datetime.date.today()).days
    if days_out == 0:
        day = ''
    elif days_out == 1:
        day = 'tomorrow '
    else:
        day = when.strftime('%a %b ') + str(when.day) + ' '
    minutes = max(0, int((ts - now) // 60))
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    rel = '%dd %dh' % (days, hours) if days else ('%dh %dm' % (hours, minutes) if hours else '%dm' % minutes)
    return '%s%s (in %s)' % (day, clock, rel)


def describe(key, w, now):
    name = NAMES.get(key, key.replace('_', ' ') + ' limit')
    if key == 'spend_limit' and w.get('period') in ('daily', 'weekly', 'monthly'):
        name = '%s spend limit' % w['period']
    text = '%d%% of your %s used' % (math.floor(w['used_percentage']), name)
    used, limit = w.get('used_usd'), w.get('limit_usd')
    if isinstance(used, NUM) and isinstance(limit, NUM):
        text += ' ($%.2f of $%.2f)' % (used, limit)
    return '%s — resets %s' % (text, resets_text(w['resets_at'], now))


now = time.time()
windows = load(usage_path).get('rate_limits')
if not isinstance(windows, dict):
    raise SystemExit(0)

previous = load(warned_path)
# Forget windows that have reset, so the next fill warns again.
warned = {k: v for k, v in previous.items() if isinstance(v, NUM) and v > now}

messages = []
for key, w in windows.items():
    if not isinstance(w, dict):
        continue
    pct, resets = w.get('used_percentage'), w.get('resets_at')
    if not isinstance(pct, NUM) or not isinstance(resets, NUM) or resets <= now or pct < WARN:
        continue
    if key in warned and abs(warned[key] - resets) < SAME_WINDOW_SECONDS:
        continue
    warned[key] = resets
    messages.append(describe(key, w, now))

if warned != previous:
    try:
        os.makedirs(cache_dir, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=cache_dir, prefix='.usage-warned-')
        with os.fdopen(fd, 'w') as f:
            json.dump(warned, f)
        os.replace(tmp, warned_path)
    except Exception:
        pass

if messages:
    body = '\n'.join('  • ' + m for m in messages) if len(messages) > 1 else messages[0]
    sep = '\n' if len(messages) > 1 else ' '
    print(json.dumps({'systemMessage': '⚠️ Claude usage:%s%s. Run /usage for details.' % (sep, body)}))
PY

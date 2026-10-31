#!/usr/bin/env python3
"""Pull the signals a meta-improvement pass needs from the last N minutes of a Claude Code session transcript.

    python3 -I signals.py [--since 60] [--transcript PATH] [--cwd DIR]

Without --transcript it picks the most recently written transcript for --cwd (default: the current directory) under
$CLAUDE_CONFIG_DIR or ~/.claude*/projects. Prints compact markdown:
  - every user message (typed, queued mid-turn, interruptions), oldest first, with times
  - tool errors grouped by tool, with the first line of each
  - tool calls by name, files written or edited 3+ times, commands run 3+ times
Reads the transcript backwards in blocks so a large file costs only the window it needs. Read-only; never prints secrets
it did not find in the user's own messages, and truncates long text.
"""
import argparse, glob, json, os, re, sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

def find_transcript(cwd):
    roots = [os.environ.get('CLAUDE_CONFIG_DIR', '')] + glob.glob(os.path.expanduser('~/.claude*'))
    slug = re.sub(r'[^A-Za-z0-9]', '-', os.path.abspath(cwd))
    files = [f for r in roots if r for f in glob.glob(os.path.join(r, 'projects', slug, '*.jsonl'))]
    return max(files, key=os.path.getmtime) if files else None

def tail_records(path, since):
    """Yield parsed records newer than `since`, reading the file backwards in blocks."""
    size, block, buf, out = os.path.getsize(path), 4 << 20, b'', []
    with open(path, 'rb') as f:
        pos = size
        while pos > 0:
            pos = max(0, pos - block); f.seek(pos); chunk = f.read(min(block, size - pos)) + buf
            lines = chunk.split(b'\n'); buf = lines[0] if pos > 0 else b''
            older = False
            for line in reversed(lines[1:] if pos > 0 else lines):
                try: o = json.loads(line)
                except Exception: continue
                ts = o.get('timestamp')
                if ts:
                    t = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                    if t < since: older = True; continue
                    o['_t'] = t
                out.append(o)
            if older: break
    return [o for o in reversed(out) if '_t' in o]

def text_of(content):
    if isinstance(content, str): return content
    if isinstance(content, list): return ' '.join(x.get('text', '') for x in content if isinstance(x, dict) and x.get('type') == 'text')
    return ''

def clip(s, n=500): s = ' '.join(s.split()); return s if len(s) <= n else s[:n] + ' …'

if __name__ == '__main__':
    a = argparse.ArgumentParser(); a.add_argument('--since', type=int, default=60); a.add_argument('--transcript'); a.add_argument('--cwd', default=os.getcwd())
    a.add_argument('--human', action='store_true', help='only count messages the user wrote (not timer firings or summaries); exit 1 if none')
    o = a.parse_args()
    path = o.transcript or find_transcript(o.cwd)
    if not path: sys.exit('no transcript found for ' + o.cwd)
    since = datetime.now(timezone.utc) - timedelta(minutes=o.since)
    recs = tail_records(path, since)
    users, errors, tools, writes, cmds = [], defaultdict(list), Counter(), Counter(), Counter()
    for r in recs:
        t = r['_t'].astimezone().strftime('%H:%M'); m = r.get('message') or {}
        if r.get('type') == 'user' and isinstance(m.get('content'), (str, list)):
            if isinstance(m['content'], list) and any(isinstance(x, dict) and x.get('type') == 'tool_result' for x in m['content']):
                for x in m['content']:
                    if isinstance(x, dict) and x.get('type') == 'tool_result' and x.get('is_error'):
                        c = x.get('content'); c = c if isinstance(c, str) else text_of(c); errors[x.get('tool_use_id', '')[:0] or 'tool'].append(clip(c.split('\n')[0], 160))
                continue
            s = text_of(m['content']).strip()
            if s and not s.startswith('<'): users.append((t, 'typed', clip(s)))
            elif '[Request interrupted' in s: users.append((t, 'interrupt', ''))
        elif r.get('type') == 'queue-operation' and r.get('operation') == 'enqueue' and r.get('content') and not str(r['content']).lstrip().startswith('<'):
            users.append((t, 'mid-turn', clip(str(r['content']))))
        elif r.get('type') == 'assistant':
            for x in m.get('content') or []:
                if isinstance(x, dict) and x.get('type') == 'tool_use':
                    tools[x.get('name')] += 1; inp = x.get('input') or {}
                    if x.get('name') in ('Edit', 'Write') and inp.get('file_path'): writes[inp['file_path']] += 1
                    if x.get('name') == 'Bash' and inp.get('command'): cmds[clip(inp['command'].split('\n')[0], 90)] += 1
    seen = set(); users = [u for u in users if not (u[2] and u[2] in seen) and not seen.add(u[2])]   # a queued message is also logged when typed
    if o.human:   # the cheap check a timer firing runs first: did the user say anything this hour?
        bot = ('/meta-improve', 'Base directory for this skill:', 'This session is being continued')
        fires = [i for i, (_, _, txt) in enumerate(users) if txt.startswith('/meta-improve')]
        since = fires[-2] + 1 if len(fires) >= 2 else 0   # only what came after the previous pass (the last firing is this one)
        n = sum(1 for _, k, txt in users[since:] if k != 'interrupt' and not txt.startswith(bot))
        print(f'{n} message(s) from the user in the last {o.since} min'); sys.exit(0 if n else 1)
    span = f"{recs[0]['_t'].astimezone():%H:%M}-{recs[-1]['_t'].astimezone():%H:%M}" if recs else 'empty'
    print(f'# Signals, last {o.since} min ({span}), {os.path.basename(path)}\n')
    print(f'## User messages ({len(users)})'); [print(f'- {t} [{k}] {s}') for t, k, s in users] or print('- none')
    n_err = sum(len(v) for v in errors.values()); print(f'\n## Tool errors ({n_err})')
    for k, v in errors.items(): [print(f'- {e}') for e in v[:12]]
    print('\n## Tool calls\n- ' + ', '.join(f'{k} {v}' for k, v in tools.most_common()))
    hot = [(f, n) for f, n in writes.most_common() if n >= 3]; print('\n## Files edited 3+ times'); [print(f'- {n}x {f}') for f, n in hot] or print('- none')
    rep = [(c, n) for c, n in cmds.most_common() if n >= 3]; print('\n## Commands run 3+ times'); [print(f'- {n}x `{c}`') for c, n in rep[:10]] or print('- none')

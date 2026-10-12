# switch-login

Run two Claude Code accounts on one machine and move a live session between them.

- `claude` runs the default account (`~/.claude`).
- `claude2` runs a second account from its own profile directory.
- An optional machine-local name exposes the same profile as `claude-<name>`.
- `/switch-login` restarts the current session in the same pane on the other
  account, with the conversation resumed. Other panes are not affected.

Both profiles share settings, skills, plugins, project memory and transcripts.
Each keeps its own credentials. Shell: bash or zsh.

## Setup

### 1 and 2. Run the installer

```sh
bash switch-login/scripts/setup.sh            # second profile in ~/.claude-2
bash switch-login/scripts/setup.sh ~/elsewhere   # or any directory
bash switch-login/scripts/setup.sh --name work   # also add claude-work
```

Or run `/setup-switch-login` in a Claude session. The script:

- creates the second profile and links the shared entries of `~/.claude` into it
  (`CLAUDE.md settings.json skills plugins projects todos file-history
  history.jsonl session-env shell-snapshots`; missing ones are skipped);
- installs or refreshes this skill (and the `new` skill, when it sits next to
  it) in `~/.claude/skills/`;
- backs up your rc file and adds two lines to it (`~/.zshrc` for zsh, otherwise
  `~/.bashrc`; pick one with `--rc FILE`).

It is safe to run twice. It refuses to change anything when a path it would
create already exists as something else, and prints what it found.
`bash switch-login/scripts/setup-test.sh` checks it against a temporary `HOME`.

Then open a new shell, run `claude2`, and `/login` with the second account.

#### By hand (what the script does)

```sh
P="$HOME/.claude-2"          # any directory; this is the second profile
mkdir -p "$P"
for f in CLAUDE.md settings.json skills plugins projects todos \
         file-history history.jsonl session-env shell-snapshots; do
  [ -e "$HOME/.claude/$f" ] && ln -s "$HOME/.claude/$f" "$P/$f"
done
cp -r switch-login ~/.claude/skills/
```

Do not link `.credentials.json`, `.claude.json` or `sessions/`: they stay private
to each profile. `projects` must be linked, or a switched session cannot find
its transcript.

Add to `~/.bashrc` or `~/.zshrc`, then open a new shell, run `claude2` and `/login`:

```sh
export CLAUDE_LOGIN2_DIR="$HOME/.claude-2"
export CLAUDE_LOGIN2_NAME="work" # optional: adds claude-work
source "$HOME/.claude/skills/switch-login/claude-login.sh"
```

(`claude-login.zsh` still works for existing `~/.zshrc` lines; it sources `claude-login.sh`.)

### 3. Check

- `type claude` and `type claude2` say they are functions ("shell function" in
  zsh, "function" in bash). If `CLAUDE_LOGIN2_NAME` is set, so does
  `type claude-<name>`.
- `claude2`, then `/status`, shows the second account.
- In a `claude` session, send one message and run `/switch-login`. The pane
  prints `switch-login: resuming on the second account` and the conversation
  continues.

## How it works

A running session cannot change account by itself: every session of a profile
reads the same credentials file. So `scripts/switch.sh` writes the session id
to the file named in `$CLAUDE_SWITCH_FILE` and stops the current `claude`
process. The `claude` shell function (`claude-login.sh`) sees that file and
starts `claude --resume <id>` under the other profile, with the flags the
session was started with.

The resumed session starts with `--remote-control` when the old one had Remote
Control on (`$CLAUDE_CODE_BRIDGE_SESSION_ID` is set), or when you run
`/switch-login rc`. That way, if you are driving the session from the Claude app,
it shows up there again after the switch.

A session that was started before the wrapper was loaded has no
`$CLAUDE_SWITCH_FILE`. The script then resumes it in a new tmux session on the
other account, with Remote Control on, through the `new` skill's launcher, and
stops the old process. This works with no one at the machine. Without tmux or
the `new` skill, it prints the command to run by hand.

## Limits

- bash or zsh.
- Two accounts only.
- `scripts/switch.sh` stops the session through `$CLAUDE_PID`, which Claude Code sets in the session environment.

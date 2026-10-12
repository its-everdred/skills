# Sourced from ~/.bashrc or ~/.zshrc, after CLAUDE_LOGIN2_DIR is set to the
# second account's profile directory. Works in bash and zsh. Wraps `claude` so
# /switch-login can restart the session in place on the other account: the skill
# writes the session id to $CLAUDE_SWITCH_FILE and stops claude; this loop then
# resumes that session under the other profile.
#
# Switch file format: line 1 is the session id. An optional line 2 of "rc" asks
# for the resumed session to start with Remote Control on (--remote-control), so
# a user driving the session from the Claude app can pick it up again.
_claude_login () {
  local who=$1 runtime f id rc a n skip has_rc st
  runtime=${XDG_RUNTIME_DIR:-/tmp}
  [ -d "$runtime" ] && [ -w "$runtime" ] || runtime=/tmp
  f=$(mktemp "$runtime/claude-switch.XXXXXX") || return 1
  shift
  while :; do
    if [ "$who" = second ]; then
      CLAUDE_SWITCH_FILE=$f CLAUDE_CONFIG_DIR="${CLAUDE_LOGIN2_DIR:?set CLAUDE_LOGIN2_DIR to the second profile directory}" command claude "$@"; st=$?
    else
      CLAUDE_SWITCH_FILE=$f command claude "$@"; st=$?
    fi
    if [ ! -s "$f" ]; then rm -f -- "$f"; return "$st"; fi
    id=$(sed -n 1p "$f"); rc=$(sed -n 2p "$f"); rm -f "$f"
    if [ "$who" = second ]; then who=default; else who=second; fi
    # Keep the original flags, but replace any session selection with the resume.
    n=$#; skip=0; has_rc=0
    while [ "$n" -gt 0 ]; do
      a=$1; shift; n=$((n - 1))
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      case $a in
        -c|--continue|--resume=*) ;;
        -r|--resume) skip=1 ;;
        --remote-control*) has_rc=1; set -- "$@" "$a" ;;
        *) set -- "$@" "$a" ;;
      esac
    done
    set -- "$@" --resume "$id"
    if [ "$rc" = rc ] && [ "$has_rc" = 0 ]; then set -- "$@" --remote-control; fi
    stty sane 2>/dev/null
    printf 'switch-login: resuming on the %s account\n' "$who"
  done
}
claude () { _claude_login default "$@"; }
claude2 () { _claude_login second "$@"; }
if [ -n "${CLAUDE_LOGIN2_NAME:-}" ]; then
  case "$CLAUDE_LOGIN2_NAME" in
    *[!A-Za-z0-9_-]*)
      printf 'switch-login: ignoring invalid CLAUDE_LOGIN2_NAME: %s\n' "$CLAUDE_LOGIN2_NAME" >&2
      ;;
    *)
      _claude_login_named_command="claude-$CLAUDE_LOGIN2_NAME"
      eval "$_claude_login_named_command () { _claude_login second \"\$@\"; }"
      unset _claude_login_named_command
      ;;
  esac
fi

# Sourced from ~/.zshrc, after CLAUDE_LOGIN2_DIR is set to the second account's
# profile directory. Wraps `claude` so /switch-login can restart the session in
# place on the other account: the skill writes the session id to $CLAUDE_SWITCH_FILE
# and stops claude; this loop then resumes that session under the other profile.
_claude_login () {
  local who=$1 f=${XDG_RUNTIME_DIR:-/tmp}/claude-switch-$$-$RANDOM id i
  shift
  local -a base=("$@")
  while :; do
    if [[ $who == second ]]; then
      CLAUDE_SWITCH_FILE=$f CLAUDE_CONFIG_DIR="${CLAUDE_LOGIN2_DIR:?set CLAUDE_LOGIN2_DIR to the second profile directory}" command claude "$@"
    else
      CLAUDE_SWITCH_FILE=$f command claude "$@"
    fi
    [[ -s $f ]] || return
    id=$(<$f); rm -f $f
    [[ $who == second ]] && who=default || who=second
    # Keep the original flags, but replace any session selection with the resume.
    base=("${(@)base:#(-c|--continue)}")
    i=${base[(i)(-r|--resume)]}
    (( i <= $#base )) && base[i,i+1]=()
    set -- "${base[@]}" --resume $id
    stty sane
    print "switch-login: resuming on the $who account"
  done
}
claude () { _claude_login default "$@" }
claude2 () { _claude_login second "$@" }

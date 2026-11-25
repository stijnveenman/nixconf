# Popups start in herdr's own directory: move to the pane that was focused.
cwd=$("$herdr" pane get "${HERDR_ACTIVE_PANE_ID:-}" 2>/dev/null |
  "$jq" -r '.result.pane | .foreground_cwd // .cwd // empty' 2>/dev/null) || cwd=
[ -z "$cwd" ] || cd "$cwd" || :

status=0
"$wt_start" || status=$?
if [ "$status" -ne 0 ]; then
  # The popup closes with the command; keep the error readable.
  printf '\nPress enter to close.'
  read -r _ || :
fi
exit "$status"

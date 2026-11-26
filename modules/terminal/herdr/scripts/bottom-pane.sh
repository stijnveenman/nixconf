# Run a command in a pane split below the focused pane (15% high); the pane
# closes when the command exits. Usage: bottom-pane <command> [args...]
set -euo pipefail

pane=$(herdr pane split --pane "${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:?no pane id in env}}" --direction down --ratio 0.85 --focus | jq -r '.result.pane.pane_id')
cmd=$(printf '%q ' "$@")
herdr pane run "$pane" "printf '\\033[?1049h\\033[H'; exec $cmd"

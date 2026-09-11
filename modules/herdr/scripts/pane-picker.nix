{
  pkgs,
  lib,
}: let
  herdrBin = lib.getExe pkgs.herdr;
  jqBin = lib.getExe pkgs.jq;
  awkBin = lib.getExe pkgs.gawk;
  fzfBin = lib.getExe pkgs.fzf;
in
  pkgs.writeShellScript "herdr-pane-picker" ''
    set -euo pipefail

    workspaces_json=$(${herdrBin} workspace list)

    candidates=$(
      printf '%s' "$workspaces_json" | ${jqBin} -r '
        .result.workspaces[]
        | [
            .workspace_id,
            (.number | tostring),
            (.label // .workspace_id)
          ]
        | @tsv
      ' | while IFS=$'\t' read -r workspace_id workspace_number workspace_label; do
        branch=$(
          ${herdrBin} worktree list --workspace "$workspace_id" 2>/dev/null | ${jqBin} -r --arg workspace_id "$workspace_id" '
            [ .result.worktrees[]? | select(.open_workspace_id == $workspace_id) | .branch ][0] // empty
          '
        )

        printf '%s\t%s\t%s\t%s\n' "$workspace_id" "$workspace_number" "$workspace_label" "$branch"
      done
    )

    if [ -z "$candidates" ]; then
      ${herdrBin} notification show "No workspaces found" --position top-right >/dev/null 2>&1
      exit 0
    fi

    widths=$(printf '%s\n' "$candidates" | ${awkBin} -F $'\t' '
      BEGIN {
        number_width = length("number")
        label_width = length("label")
      }
      length($2) > number_width { number_width = length($2) }
      length($3) > label_width { label_width = length($3) }
      END { printf "%d\t%d\n", number_width, label_width }
    ')
    number_width=$(printf '%s' "$widths" | cut -f1)
    label_width=$(printf '%s' "$widths" | cut -f2)

    display_candidates=$(
      printf '__header__\t%-*s\t%-*s\t%s\n' "$number_width" "number" "$label_width" "label" "branch"

      printf '%s\n' "$candidates" | while IFS=$'\t' read -r workspace_id workspace_number workspace_label workspace_branch; do
        printf '%s\t%-*s\t%-*s\t%s\n' "$workspace_id" "$number_width" "$workspace_number" "$label_width" "$workspace_label" "$workspace_branch"
      done
    )

    selected=$(
      printf '%s\n' "$display_candidates" | ${fzfBin} \
        --delimiter=$'\t' \
        --with-nth='2,3,4' \
        --header-lines=1 \
        --prompt='Workspace > ' \
        --height=100% \
        --layout=reverse \
        --border
    ) || exit 0

    target_workspace=$(printf '%s' "$selected" | cut -f1)
    ${herdrBin} workspace focus "$target_workspace" >/dev/null
  ''

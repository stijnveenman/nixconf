{
  pkgs,
  lib,
  config,
  treehouse,
  ...
}: let
  # Herdr processes may not inherit the Nix profile on PATH.
  herdrBin = lib.getExe config.programs.herdr.package;
  jqBin = lib.getExe pkgs.jq;
  gumBin = lib.getExe pkgs.gum;
  gitBin = lib.getExe pkgs.git;
  fzfBin = lib.getExe pkgs.fzf;
  awkBin = lib.getExe pkgs.gawk;
  direnvBin = lib.getExe config.programs.direnv.package;

  interactiveShell =
    if config.programs.zsh.enable
    then config.programs.zsh.package
    else config.programs.bash.package;

  # Cycle through agents by attention priority: blocked, done, then idle.
  nextAgentScript = pkgs.writeShellScript "herdr-next-agent" ''
    agents=$(${herdrBin} agent list) || exit 1

    target=$(printf '%s' "$agents" | ${jqBin} -r '
      ["blocked","done","idle"] as $prio
      | .result.agents
      | map(.rank = (.agent_status as $s | $prio | index($s)))
      | map(select(.rank != null))
      | sort_by(.rank)
      | . as $ranked
      | ($ranked | map(.focused) | index(true)) as $cur
      | if ($ranked | length) == 0 then ""
        elif $cur == null then $ranked[0].pane_id
        else $ranked[(($cur + 1) % ($ranked | length))].pane_id
        end
    ')

    if [ -z "$target" ]; then
      ${herdrBin} notification show "No agent needs attention" --position top-right >/dev/null 2>&1
      exit 0
    fi

    ${herdrBin} agent focus "$target" >/dev/null 2>&1
  '';

  panePickerScript = pkgs.writeShellScript "herdr-pane-picker" ''
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
  '';

  # Fetch the latest nixconf changes and switch the home configuration,
  # driven from the directory set through NH_HOME_FLAKE (herdr processes may
  # not inherit the Nix profile, so fall back to the macbook's flake dir).
  switchNixconfScript = pkgs.writeShellScript "herdr-switch-nixconf" ''
    set -euo pipefail

    # Set the terminal title so the popup top bar shows a friendly name.
    printf '\033]0;nixconf switch\007'

    flake_dir=''${NH_HOME_FLAKE:-/Users/sv/Documents/nixconf}

    if [ ! -d "$flake_dir" ]; then
      ${gumBin} style --foreground red "nixconf directory not found: $flake_dir"
      exit 1
    fi

    ${gumBin} style --foreground cyan "Switching nixconf from $flake_dir"
    cd "$flake_dir" || exit 1

    # Stage 1: fetch
    ${gumBin} style --foreground cyan "Fetching latest nixconf from origin main..."
    if ! git pull --ff-only origin main; then
      ${gumBin} style --foreground red "Fetch failed (diverged or no upstream?). Fix it and retry."
      read -s -n1 -p "Press any key to close..."
      exit 1
    fi

    # Stage 2: switch
    ${gumBin} style --foreground cyan "Switching nixconf home configuration..."
    if ! nh home switch "$flake_dir"; then
      ${gumBin} style --foreground red "nh home switch failed, see errors above."
      read -s -n1 -p "Press any key to close..."
      exit 1
    fi

    # Stage 3: reload herdr config so new keybindings take effect immediately.
    ${herdrBin} server reload-config >/dev/null 2>&1 || true

    ${gumBin} style --foreground green "nixconf switched successfully."
    read -s -n1 -p "Press any key to close..."
  '';
  # Fires on every `treehouse get` acquisition (new or recycled worktree —
  # treehouse's post_create hook re-runs on pool reuse, not just first
  # creation). No-ops for every repo except airport-control. airport-control's
  # own .envrc sets `nix_direnv_manual_reload`, which means even a brand-new
  # worktree's first `direnv allow` will NOT build the nix-direnv cache on its
  # own — so a forced reload is required to actually get flake packages like
  # git-crypt onto PATH.
  airportControlPostCreateHook = pkgs.writeShellScript "treehouse-post-create-airport-control" ''
    set -eu

    dir="$PWD"   # treehouse runs post_create hooks with cwd = the new worktree

    remote_url=$(${gitBin} -C "$dir" remote get-url origin 2>/dev/null) || exit 0

    case "$remote_url" in
      https://github.com/schiphol-ac/airport-control | \
      https://github.com/schiphol-ac/airport-control.git | \
      git@github.com:schiphol-ac/airport-control | \
      git@github.com:schiphol-ac/airport-control.git)
        ;;
      *)
        exit 0
        ;;
    esac

    ${direnvBin} allow "$dir"
    # Reproduces nix-direnv's own generated nix-direnv-reload script
    # (.direnv/bin/nix-direnv-reload) without depending on it existing or on
    # PATH: forces a rebuild even when the project's .envrc opts out of
    # automatic reload via nix_direnv_manual_reload.
    _nix_direnv_force_reload=1 ${direnvBin} exec "$dir" true
  '';
in {
  home.packages = [
    treehouse
    pkgs.gum
  ];

  home.file.".config/treehouse/config.toml".text = ''
    max_trees = 12

    [hooks]
    post_create = ["${airportControlPostCreateHook}"]
  '';

  programs.herdr = {
    enable = true;
    package = pkgs.herdr;
    settings = {
      onboarding = false;

      theme.name = "gruvbox";

      theme.custom = {
        active_row_bg = "#665c54";
        selection_bg = "#665c54";
      };

      keys.prefix = "ctrl+f";

      keys.previous_workspace = "prefix+[";
      keys.next_workspace = "prefix+]";
      keys.switch_workspace = "prefix+shift+1..9";

      keys.open_worktree = "prefix+ctrl+shift+g";

      keys.command = [
        {
          # Use an interactive shell so hooks inherit the normal terminal PATH.
          key = "ctrl+g";
          type = "shell";
          command = pkgs.writeShellScript "lazygit pane" ''
            PANE=$(herdr pane split $HERDR_PANE_ID --direction right --ratio 0.5 --focus | jq '.result.pane.pane_id' -r)
            herdr pane run $PANE '${lib.getExe pkgs.lazygit} && exit'
          '';
          description = "lazygit";
        }
        {
          key = "prefix+ctrl+r";
          type = "popup";
          command = "${lib.getExe interactiveShell} -i -c 'exec ${switchNixconfScript}'";
          width = 90;
          height = 24;
          description = "fetch and switch nixconf";
        }
        {
          key = "prefix+space";
          type = "popup";
          command = "${lib.getExe interactiveShell} -i -c 'exec ${panePickerScript}'";
          width = 100;
          height = 28;
          description = "fzf workspace picker";
        }
        {
          key = "prefix+o";
          type = "shell";
          command = "${nextAgentScript}";
          description = "next agent needing attention";
        }

        # smart-splits is cloned at runtime, so link its plugin once:
        #   herdr plugin link ~/.local/share/nvim-nixconf/lazy/smart-splits.nvim
        #   herdr server reload-config
        {
          key = "ctrl+h";
          type = "plugin_action";
          command = "smart-splits.nvim.left";
          description = "navigate left (vim/herdr)";
        }
        {
          key = "ctrl+j";
          type = "plugin_action";
          command = "smart-splits.nvim.down";
          description = "navigate down (vim/herdr)";
        }
        {
          key = "ctrl+k";
          type = "plugin_action";
          command = "smart-splits.nvim.up";
          description = "navigate up (vim/herdr)";
        }
        {
          key = "ctrl+l";
          type = "plugin_action";
          command = "smart-splits.nvim.right";
          description = "navigate right (vim/herdr)";
        }
      ];

      ui = {
        status_indicators = "symbols";
        toast.delivery = "herdr";

        prompt_new_tab_name = false;
      };
    };
  };
}

{
  lib,
  pkgs,
  workmux,
}: let
  gh = lib.getExe pkgs.gh;
  jq = lib.getExe pkgs.jq;
  perl = lib.getExe pkgs.perl;
  tmux = lib.getExe pkgs.tmux;
  workmuxPackage = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workmuxExe = lib.getExe' workmuxPackage "workmux";
in
  pkgs.writeShellScript "workmux-sidebar-open-pr" ''
    set -uo pipefail

    notify() {
      ${tmux} display-message -d 5000 "workmux sidebar: $*" 2>/dev/null || printf 'workmux sidebar: %s\n' "$*" >&2
    }

    # The workmux sidebar is a tagged tmux pane. Query the current window so a
    # session with sidebars in other windows does not produce a stale result.
    if ! currentWindow="$(${tmux} display-message -p '#{window_id}' 2>/dev/null)"; then
      notify 'no current tmux client'
      exit 1
    fi

    tab="$(printf '\t')"
    sidebarPane=""
    while IFS="$tab" read -r pane role; do
      if [ "$role" = sidebar ]; then
        sidebarPane="$pane"
        break
      fi
    done < <(${tmux} list-panes -t "$currentWindow" -F "#{pane_id}$tab#{@workmux_role}" 2>/dev/null)

    if [ -z "$sidebarPane" ]; then
      notify 'no workmux sidebar in the current tmux window'
      exit 1
    fi

    if ! sidebar="$(${tmux} capture-pane -p -e -t "$sidebarPane" 2>/dev/null)"; then
      notify 'could not capture the sidebar pane'
      exit 1
    fi

    # `capture-pane -e` preserves SGR attributes. Workmux renders the selected
    # tile with a background colour, which can persist across terminal lines
    # without being repeated. The second and third configured template lines
    # hold the repository and PR number respectively.
    if ! selected="$(printf '%s\n' "$sidebar" | ${perl} -CS -e '
      use strict;
      use warnings;

      my $background = 0;
      my @selected_lines;
      my @selected_tiles;

      sub apply_sgr {
        my ($parameters) = @_;
        $parameters = "0" if $parameters eq "";
        for my $parameter (split /;/, $parameters) {
          my ($code) = split /:/, $parameter;
          $background = 0 if $code == 0 || $code == 49;
          $background = 1 if ($code >= 40 && $code <= 48) || ($code >= 100 && $code <= 107);
        }
      }

      while (defined(my $line = <STDIN>)) {
        my ($offset, $selected) = (0, 0);
        while ($line =~ /\e\[([0-9;:]*)m/g) {
          $selected ||= $background && $-[0] > $offset;
          apply_sgr($1);
          $offset = $+[0];
        }
        $selected ||= $background && length($line) > $offset;

        $line =~ s/\e\[[0-?]*[ -\/]*[@-~]//g;
        $line =~ s/\r?\n\z//;
        if ($selected) {
          push @selected_lines, $line;
        } elsif (@selected_lines) {
          push @selected_tiles, [@selected_lines];
          @selected_lines = ();
        }
      }
      push @selected_tiles, [@selected_lines] if @selected_lines;

      exit 1 unless @selected_tiles;
      my $repository_line = $selected_tiles[0][1] // q{};
      my $pr_line = $selected_tiles[0][2] // q{};
      $repository_line =~ s/^\s*\S+\s+//;
      $repository_line =~ /^\s*(\S+)/ or exit 0;
      my $repository = $1;
      $pr_line =~ /(#\d+)/ or exit 0;
      print "$repository\t$1\n";
    ')"; then
      notify 'could not parse the selected sidebar tile'
      exit 1
    fi

    if [ -z "$selected" ]; then
      notify 'no GitHub pull request in the selected sidebar row'
      exit 1
    fi

    IFS="$tab" read -r repository prNumber <<<"$selected"

    if ! projectPath="$(${workmuxExe} list --all --json | ${jq} -r --arg project "$repository" '[.[] | select(.project == $project) | .project_path][0] // empty')" || [ -z "$projectPath" ]; then
      notify "could not resolve workmux project: $repository"
      exit 1
    fi

    if ! (cd "$projectPath" && ${gh} pr view "''${prNumber#\#}" --web); then
      notify "could not open pull request $prNumber for $repository"
      exit 1
    fi
  ''

{
  lib,
  pkgs,
  workmux,
  ...
}: let
  tmux = lib.getExe pkgs.tmux;
  workmuxPackage = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workmuxExe = lib.getExe' workmuxPackage "workmux";
in {
  home.packages = [workmuxPackage];

  programs.zsh.initContent = lib.mkAfter ''
    # Apply the workmux wrappers only inside the tmux-tpad scratchpad session.
    __tpad_workmux_setup() {
      [[ -n "''${TMUX-}" ]] || return

      local current_session argument
      current_session="$(${tmux} display-message -p '#S' 2>/dev/null)" || return
      [[ "$current_session" == tpad_scratchpad* ]] || return

      workmux() {
        if [[ "$1" == add ]]; then
          for argument in "$@"; do
            if [[ "$argument" == --background || "$argument" == --background=* ]]; then
              command ${workmuxExe} "$@"
              return
            fi
          done

          shift
          command ${workmuxExe} add --background "$@"
        elif [[ "$1" == open || "$1" == close ]]; then
          command ${workmuxExe} "$@" &
        else
          command ${workmuxExe} "$@"
        fi
      }

      typeset -g __tpad_workmux_configured=1
    }

    __tpad_workmux_hook() {
      [[ -n "''${__tpad_workmux_configured-}" ]] || __tpad_workmux_setup
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __tpad_workmux_hook
    __tpad_workmux_hook
  '';

  xdg.configFile."workmux/config.yaml".source = ./config.yaml;
}

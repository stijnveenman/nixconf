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
    # FLOAX_SESSION_NAME is global to the tmux server, so use it only as the
    # configured target session after confirming this shell's current session.
    __floax_workmux_setup() {
      [[ -n "''${TMUX-}" ]] || return

      local current_session floax_session argument
      current_session="$(${tmux} display-message -p '#S' 2>/dev/null)" || return
      floax_session="$(${tmux} show-environment -g FLOAX_SESSION_NAME 2>/dev/null)" || return
      [[ "$floax_session" == FLOAX_SESSION_NAME=* ]] || return
      floax_session="''${floax_session#FLOAX_SESSION_NAME=}"
      [[ "$current_session" == "$floax_session" ]] || return

      command ${workmuxExe} sidebar --session off

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

      typeset -g __floax_workmux_configured=1
    }

    __floax_workmux_hook() {
      [[ -n "''${__floax_workmux_configured-}" ]] || __floax_workmux_setup
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __floax_workmux_hook
    __floax_workmux_hook
  '';

  xdg.configFile."workmux/config.yaml".source = ./config.yaml;
}

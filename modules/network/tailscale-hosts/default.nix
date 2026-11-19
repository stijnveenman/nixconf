{
  # macOS: MagicDNS is unreliable on the work MacBook, so mirror every
  # Tailscale node into /etc/hosts once a day (and at login).
  #
  # One-time manual setup (standalone home-manager cannot manage sudoers):
  #   echo "$USER ALL=(root) NOPASSWD: /usr/bin/tee /etc/hosts" \
  #     | sudo tee /etc/sudoers.d/tailscale-hosts && sudo chmod 440 /etc/sudoers.d/tailscale-hosts
  flake.modules.homeManager.tailscale-hosts = {
    config,
    lib,
    pkgs,
    ...
  }: let
    jq = lib.getExe pkgs.jq;

    tailscale-hosts = pkgs.writeShellScript "tailscale-hosts" ''
      jq=${lib.escapeShellArg jq}
      ${builtins.readFile ./scripts/tailscale-hosts.sh}
    '';

    logFile = "${config.home.homeDirectory}/Library/Logs/tailscale-hosts.log";
  in {
    # Run on demand with `tailscale-hosts`.
    home.file.".local/bin/tailscale-hosts".source = tailscale-hosts;

    launchd.agents.tailscale-hosts = {
      enable = true;
      config = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          "/bin/wait4path /nix/store && exec ${tailscale-hosts}"
        ];
        RunAtLoad = true;
        StartCalendarInterval = [
          {
            Hour = 9;
            Minute = 7;
          }
        ];
        StandardOutPath = logFile;
        StandardErrorPath = logFile;
      };
    };
  };
}

# Keeps `claude remote-control` running as a systemd user service, so the
# machine is always reachable from claude.ai/code (and scheduled tasks). Log in
# once interactively with `claude` first; the service reuses those credentials.
# The host needs `users.users.<name>.linger = true` to start it without a login.
{
  flake.modules.homeManager.claude-remote-control = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.claudeRemoteControl;
    claude = lib.getExe pkgs.claude-code;
  in {
    options.my.claudeRemoteControl.directory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/nixconf";
      description = "Directory Remote Control sessions start in.";
    };

    config = {
      home.packages = [pkgs.claude-code];

      systemd.user.services.claude-remote-control = {
        Unit.Description = "Claude Code Remote Control";
        Service = {
          WorkingDirectory = cfg.directory;
          ExecStart = "${claude} remote-control";
          # Sessions need the user's tools (git, nix, nh), not systemd's PATH.
          Environment = [
            "PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
          ];
          Restart = "always";
          RestartSec = 30;
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}

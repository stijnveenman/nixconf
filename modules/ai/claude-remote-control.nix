# Keeps `claude remote-control` running as systemd user services (one per
# directory), so the machine is always reachable from claude.ai/code (and
# scheduled tasks). Log in once interactively with `claude` first; the services
# reuse those credentials.
# The host needs `users.users.<name>.linger = true` to start them without a login.
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
    options.my.claudeRemoteControl.directories = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {nixconf = "${config.home.homeDirectory}/nixconf";};
      description = ''
        Directories Remote Control sessions start in, keyed by name. Each gets
        its own `claude-remote-control-<name>` user service.
      '';
    };

    config = {
      home.packages = [pkgs.claude-code];

      systemd.user.services = lib.mapAttrs' (name: directory:
        lib.nameValuePair "claude-remote-control-${name}" {
          Unit.Description = "Claude Code Remote Control (${name})";
          Service = {
            WorkingDirectory = directory;
            ExecStart = "${claude} remote-control";
            # Sessions need the user's tools (git, nix, nh), not systemd's PATH.
            Environment = [
              "PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
            ];
            Restart = "always";
            RestartSec = 30;
          };
          Install.WantedBy = ["default.target"];
        })
      cfg.directories;
    };
  };
}

{
  flake.modules.homeManager.nh = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.nh;
    nh = lib.getExe pkgs.nh;
  in {
    options.my.nh = {
      subcommand = lib.mkOption {
        type = lib.types.enum ["os" "home" "darwin"];
        description = "The nh subcommand that manages this host.";
      };
      privilegedSwitch = lib.mkEnableOption ''
        `nhs` that builds as the user and activates through the passwordless
        `nixos-switch` sudo rule (NixOS module `nixos-switch`), so agents can
        switch without a prompt
      '';
      homeFlake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          When set, enable home-manager's `programs.nh` with this flake path
          and weekly garbage collection.
        '';
      };
    };

    config = {
      home.packages = [
        (pkgs.writeShellScriptBin "nhb" ''exec ${nh} ${cfg.subcommand} build "$@"'')
        (pkgs.writeShellScriptBin "nhs" (
          if cfg.privilegedSwitch
          then ''
            set -euo pipefail
            out=$(mktemp -d)
            trap 'rm -rf "$out"' EXIT
            ${nh} os build --out-link "$out/result" "$@"
            /run/wrappers/bin/sudo -n /run/current-system/sw/bin/nixos-switch "$out/result"
          ''
          else ''exec ${nh} ${cfg.subcommand} switch "$@"''
        ))
      ];

      programs.nh = lib.mkIf (cfg.homeFlake != null) {
        enable = true;
        inherit (cfg) homeFlake;
        clean = {
          enable = !pkgs.stdenv.hostPlatform.isDarwin;
          dates = "weekly";
          extraArgs = "--keep=10";
        };
      };

      # home-manager only accepts keyword schedules on Darwin, so define our own.
      launchd.agents.nh-clean = lib.mkIf (cfg.homeFlake != null && pkgs.stdenv.hostPlatform.isDarwin) {
        enable = true;
        config = {
          ProgramArguments = [
            "/bin/sh"
            "-c"
            "/bin/wait4path /nix/store && ${nh} clean user --keep-since 7d; ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 7d"
          ];
          StartCalendarInterval = [
            {
              Hour = 16;
              Minute = 30;
            }
          ];
        };
      };
    };
  };
}

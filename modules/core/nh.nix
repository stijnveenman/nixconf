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
        (pkgs.writeShellScriptBin "nhs" ''exec ${nh} ${cfg.subcommand} switch "$@"'')
      ];

      programs.nh = lib.mkIf (cfg.homeFlake != null) {
        enable = true;
        inherit (cfg) homeFlake;
        clean = {
          enable = true;
          dates = "weekly";
          extraArgs = "--keep=10";
        };
      };
    };
  };
}

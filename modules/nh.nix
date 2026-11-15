{
  config,
  lib,
  pkgs,
  ...
}: let
  nh = lib.getExe pkgs.nh;
  sub = config.my.nh.subcommand;
in {
  options.my.nh.subcommand = lib.mkOption {
    type = lib.types.enum ["os" "home" "darwin"];
    description = "The nh subcommand that manages this host.";
  };

  config.home.packages = [
    (pkgs.writeShellScriptBin "nhb" ''exec ${nh} ${sub} build "$@"'')
    (pkgs.writeShellScriptBin "nhs" ''exec ${nh} ${sub} switch "$@"'')
  ];
}

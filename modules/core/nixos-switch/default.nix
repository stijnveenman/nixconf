{
  # `nixos-switch <path>`: activate a built NixOS system without a password.
  # The sudoers rule allows only this command, so agents can switch the system
  # but cannot run anything else as root. Used by `nhs` (my.nh.privilegedSwitch).
  flake.modules.nixos.nixos-switch = {
    config,
    lib,
    pkgs,
    ...
  }: let
    nixos-switch = pkgs.writeShellScriptBin "nixos-switch" ''
      coreutils_bin=${lib.escapeShellArg "${pkgs.coreutils}/bin"}
      nix_env=${lib.escapeShellArg "${config.nix.package}/bin/nix-env"}
      nix_store=${lib.escapeShellArg "${config.nix.package}/bin/nix-store"}
      ${builtins.readFile ./scripts/nixos-switch.sh}
    '';
  in {
    environment.systemPackages = [nixos-switch];

    security.sudo.extraRules = [
      {
        groups = ["wheel"];
        # sudo doesn't follow the profile symlink when matching, so allow both.
        commands =
          map (command: {
            inherit command;
            options = ["NOPASSWD"];
          }) [
            (lib.getExe nixos-switch)
            "/run/current-system/sw/bin/nixos-switch"
          ];
      }
    ];
  };
}

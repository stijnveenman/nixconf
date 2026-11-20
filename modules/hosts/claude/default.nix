# Standalone home-manager for Claude cloud sessions (user `root`). Activated by
# the cloud environment's setup script; see README.md.
{
  config,
  inputs,
  ...
}: let
  hm = config.flake.modules.homeManager;
in {
  flake.homeConfigurations.claude = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages."x86_64-linux";
    modules = [hm.claude];
  };
}

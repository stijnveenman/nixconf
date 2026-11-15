# flake-parts plumbing. The module registry lives in ./modules.nix.
{inputs, ...}: {
  # Declares the `flake.homeConfigurations` output.
  imports = [inputs.home-manager.flakeModules.home-manager];

  systems = ["x86_64-linux" "aarch64-darwin"];

  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}

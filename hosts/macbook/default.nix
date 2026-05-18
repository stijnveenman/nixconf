{
  home-manager,
  nixpkgs,
  ...
}:
home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
  modules = [./home.nix];
}

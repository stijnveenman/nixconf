{
  home-manager,
  nixpkgs,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ./home.nix
      ../../modules/neovim.nix
    ];
  }

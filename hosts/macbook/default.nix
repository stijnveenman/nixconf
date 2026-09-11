{
  home-manager,
  nixpkgs,
  treehouse,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit treehouse;
    };
    modules = [
      ./home.nix
      ../../modules/neovim.nix
    ];
  }

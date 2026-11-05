inputs @ {
  home-manager,
  nixpkgs,
  pi,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {inherit inputs pi;};
    modules = [
      ./home.nix
      ../../modules/neovim.nix
    ];
  }

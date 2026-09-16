{
  home-manager,
  nixpkgs,
  workmux,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {inherit workmux;};
    modules = [
      ./home.nix
      ../../modules/neovim.nix
      ../../modules/workmux
    ];
  }

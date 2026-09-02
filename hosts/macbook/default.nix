{
  home-manager,
  nixpkgs,
  treehouse,
  ...
}:
home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
  extraSpecialArgs = {
    treehouse = treehouse.packages."aarch64-darwin".default;
  };
  modules = [
    ./home.nix
    ../../modules/neovim.nix
  ];
}

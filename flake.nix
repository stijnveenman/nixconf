{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    import-tree.url = "github:vic/import-tree";

    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    pi.url = "github:earendil-works/pi/stable";
    pi.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    niri.url = "github:sodiboo/niri-flake";

    claude-desktop.url = "github:heytcass/claude-desktop-linux-flake";
    claude-desktop.inputs.nixpkgs.follows = "nixpkgs";

    herdr.url = "github:herdrdev/herdr/v0.9.5";
    herdr.inputs.nixpkgs.follows = "nixpkgs";

    herdr-worktrunk = {
      url = "github:devashish2203/herdr-worktrunk/f9df9ba700b8a4f4d97ddfe3ea3eb345e80b880b";
      flake = false;
    };
    pi-web-access = {
      url = "github:nicobailon/pi-web-access";
      flake = false;
    };
    pi-subagents = {
      url = "github:gotgenes/pi-subagents";
      flake = false;
    };
    smart-splits = {
      url = "github:mrjones2014/smart-splits.nvim/0ab2e4928dc867dfea3ff1da186e69f289d8a532";
      flake = false;
    };
  };

  # Dendritic layout: every .nix file under ./modules is a flake-parts module,
  # loaded by import-tree. Paths with a `_`-prefixed segment are skipped.
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}

{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    pi.url = "github:earendil-works/pi/stable";
    pi.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    niri.url = "github:sodiboo/niri-flake";

    herdr.url = "github:herdrdev/herdr/v0.9.5";
    herdr.inputs.nixpkgs.follows = "nixpkgs";

    herdr-worktrunk = {
      url = "github:devashish2203/herdr-worktrunk/f9df9ba700b8a4f4d97ddfe3ea3eb345e80b880b";
      flake = false;
    };
    smart-splits = {
      url = "github:mrjones2014/smart-splits.nvim/0ab2e4928dc867dfea3ff1da186e69f289d8a532";
      flake = false;
    };
  };

  outputs = inputs: {
    homeConfigurations."stiixxy" = import ./hosts/stiixxy inputs;
    homeConfigurations."sv" = import ./hosts/macbook inputs;

    nixosConfigurations."nnn" = import ./hosts/nnn inputs;
    nixosConfigurations."herdr-remote" = import ./hosts/herdr-remote inputs;
  };
}

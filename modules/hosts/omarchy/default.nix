{
  self,
  inputs,
  ...
}: {
  flake.homeConfigurations.stiixxy = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {system = "x86_64-linux";};
    modules = [
      self.homeModules.nh
      {
        home.username = "stiixxy";
        home.homeDirectory = "/home/stiixxy/";
        home.stateVersion = "25.11";
      }
    ];
  };

  flake.homeModules.nh = {
    programs.nh = {
      enable = true;
      homeFlake = "/home/stiixxy/nixconf";
    };
  };
}

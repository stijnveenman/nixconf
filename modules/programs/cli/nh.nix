{
  flake.homeModules.nh = {
    config,
    lib,
    ...
  }: {
    programs.nh = {
      enable = true;
      homeFlake = lib.mkDefault "/home/${config.home.username}/nixconf";
    };
  };
}

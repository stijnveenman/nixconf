{config, ...}: {
  programs.nh = {
    enable = true;
    homeFlake = "/home/${config.home.username}/nixconf";
  };
}

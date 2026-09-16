{
  pkgs,
  workmux,
  ...
}: {
  home.packages = [workmux.packages.${pkgs.stdenv.hostPlatform.system}.default];

  xdg.configFile."workmux/config.yaml".source = ./config.yaml;
}

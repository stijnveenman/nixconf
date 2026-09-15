{worktrunk, ...}: {
  imports = [worktrunk.homeModules.default];

  programs.worktrunk = {
    enable = true;
    enableZshIntegration = true;
  };

  xdg.configFile."worktrunk/config.toml".source = ./config.toml;
}

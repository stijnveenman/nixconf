{
  config,
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  repoPath =
    if isDarwin
    then "/Users/${config.home.username}/Documents/nixconf"
    else "/home/${config.home.username}/nixconf";
in {
  home.sessionVariables.NVIM_APPNAME = "nvim-nixconf";

  home.file.".config/nvim-nixconf".source =
    config.lib.file.mkOutOfStoreSymlink "${repoPath}/nvim";

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;
    sideloadInitLua = lib.mkIf isDarwin true;
  };

  programs.lazygit = {
    enable = true;
    settings = {
      quitOnTopLevelReturn = true;
      git.overrideGpg = false;
      git.autoFetch = false;
    };
  };

  home.packages = with pkgs; [
    fd
    fzf
    gcc
    unzip
    wget
    cargo
    go
    alejandra
    ripgrep
    nodejs_22
  ];
}

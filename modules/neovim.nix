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

  home.packages = with pkgs; [
    fd
    lazygit
    fzf
    gcc
    unzip
    wget
    cargo
    go
  ];
}

{config, ...}: let
  repoPath = config.my.nixconf.liveRepoPath;
  repoSource = path:
    if repoPath == null
    then ../. + "/${path}"
    else config.lib.file.mkOutOfStoreSymlink "${repoPath}/${path}";
in {
  imports = [./repo.nix];

  programs.opencode = {
    enable = true;
    settings = {
      autoupdate = false;
      permission = {
        bash."git *" = "allow";
      };
    };
    cli = {
      theme.name = "catppuccin";
      attention = {
        notifications = true;
        sound = false;
      };
    };
    validateFiles.cli = true;
  };

  home.file.".config/opencode/skill".source = repoSource "opencode/skill";
  home.file.".config/opencode/command".source = repoSource "opencode/command";
}

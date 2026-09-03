{
  config,
  pkgs,
  ...
}: let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  repoPath =
    if isDarwin
    then "/Users/${config.home.username}/Documents/nixconf"
    else "/home/${config.home.username}/nixconf";
in {
  programs.opencode = {
    enable = true;
    settings = {
      autoupdate = false;
    };
    tui = {
      theme = "gruvbox";
      attention = {
        enabled = true;
        notifications = true;
        sound = false;
      };
    };
  };

  # opencode global skills live in the repo (edited live, like nvim). Out-of-store
  # symlink so changes apply without a rebuild. Uses the per-platform repo path
  # rather than programs.nh.homeFlake so it works on hosts without nh.
  home.file.".config/opencode/skill".source =
    config.lib.file.mkOutOfStoreSymlink "${repoPath}/opencode/skill";

  # opencode global slash commands, likewise repo-managed and live-edited.
  home.file.".config/opencode/command".source =
    config.lib.file.mkOutOfStoreSymlink "${repoPath}/opencode/command";
}

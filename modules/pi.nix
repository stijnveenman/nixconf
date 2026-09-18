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
  piPath = "${repoPath}/pi/agent";
  liveLink = path: config.lib.file.mkOutOfStoreSymlink "${piPath}/${path}";
in {
  # Keep Pi's mutable state (.pi/agent/auth.json, sessions, npm/, etc.) in the
  # home directory, while linking the configuration that is safe to edit in
  # this repository. These links intentionally do not need a Home Manager
  # rebuild after the initial activation.
  home.file = {
    ".pi/agent/settings.json".source = liveLink "settings.json";
    ".pi/agent/keybindings.json".source = liveLink "keybindings.json";
    ".pi/agent/extensions".source = liveLink "extensions";
    ".pi/agent/skills".source = liveLink "skills";
  };
}

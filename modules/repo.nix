{lib, ...}: {
  options.my.nixconf.liveRepoPath = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "/home/user/nixconf";
    description = ''
      Absolute path to a live nixconf checkout for configuration symlinks.
      When null, use the configuration included in the Nix store instead.
    '';
  };
}

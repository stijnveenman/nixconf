{
  # Imported by every module that links config out of this repo. The `key`
  # lets the module system deduplicate it when several of them are enabled.
  flake.modules.homeManager.repo = {lib, ...}: {
    key = "nixconf#homeManager.repo";

    options.my.nixconf.liveRepoPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/user/nixconf";
      description = ''
        Absolute path to a live nixconf checkout for configuration symlinks.
        When null, use the configuration included in the Nix store instead.
      '';
    };
  };
}

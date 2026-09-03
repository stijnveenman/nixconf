{
  config,
  lib,
  ...
}: {
  options.my.git = {
    userName = lib.mkOption {
      type = lib.types.str;
      default = "Stijn Veenman";
      description = "git user.name";
    };
    userEmail = lib.mkOption {
      type = lib.types.str;
      description = "git user.email (differs per host)";
    };
  };

  config.programs.git = {
    enable = true;

    settings = {
      user = {
        name = config.my.git.userName;
        email = config.my.git.userEmail;
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };

    signing = {
      signByDefault = true;
      # autodetect based on commit
      key = null;
    };
  };
}

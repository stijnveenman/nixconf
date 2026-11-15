{
  flake.modules.homeManager.git = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.git;
  in {
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
      sshSigningPublicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "ssh-ed25519 AAAA...";
        description = ''
          Public half of ~/.ssh/id_ed25519. When set, commits are signed with
          that SSH key and the key is trusted in git's allowed_signers file.
        '';
      };
    };

    config = lib.mkMerge [
      {
        programs.git = {
          enable = true;

          settings = {
            user = {
              name = cfg.userName;
              email = cfg.userEmail;
            };
            init.defaultBranch = "main";
            pull.rebase = true;
            core.pager = "";
          };

          signing = {
            signByDefault = true;
            # autodetect based on commit
            key = null;
          };
        };
      }

      (lib.mkIf (cfg.sshSigningPublicKey != null) {
        programs.git = {
          signing = {
            format = "ssh";
            key = lib.mkForce "${config.home.homeDirectory}/.ssh/id_ed25519";
          };
          settings.gpg.ssh = {
            program = lib.getExe' pkgs.openssh "ssh-keygen";
            allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
          };
        };

        xdg.configFile."git/allowed_signers".text = ''
          ${cfg.userEmail} namespaces="git" ${cfg.sshSigningPublicKey}
        '';
      })
    ];
  };
}

{
  config,
  lib,
  pkgs,
  treehouse,
  ...
}: let
  cfg = config.treehouse;

  postCreate = pkgs.writeShellScript "treehouse-post-create" ''
    set -eu

    dir="$PWD"
    remote_url=$(${lib.getExe pkgs.git} -C "$dir" remote get-url origin 2>/dev/null) || exit 0

    case "$remote_url" in
      git@github.com:*) repo="''${remote_url#git@github.com:}" ;;
      ssh://git@github.com/*) repo="''${remote_url#ssh://git@github.com/}" ;;
      https://github.com/*) repo="''${remote_url#https://github.com/}" ;;
      http://github.com/*) repo="''${remote_url#http://github.com/}" ;;
      *) exit 0 ;;
    esac

    repo="''${repo%.git}"

    case "$repo" in
      ${lib.concatMapStringsSep "\n" (
      name: "${lib.escapeShellArg name}) ${lib.escapeShellArg (toString cfg.repos.${name}.post_create)} ;;"
    ) (builtins.attrNames cfg.repos)}
      *) exit 0 ;;
    esac
  '';
in {
  options.treehouse = {
    package = lib.mkOption {
      type = lib.types.package;
      default = treehouse.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.treehouse.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The Treehouse package to install.";
    };

    max_trees = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6;
      description = "Maximum number of worktrees managed by Treehouse.";
    };

    repos = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.post_create = lib.mkOption {
          type = lib.types.package;
          description = "Script to run after creating a worktree for this repository.";
        };
      });
      default = {};
      description = "Per-repository Treehouse hooks, keyed by GitHub owner/repository.";
    };
  };

  config = {
    home.packages = [cfg.package];

    home.file.".config/treehouse/config.toml".text = ''
      max_trees = ${toString cfg.max_trees}

      [hooks]
      post_create = ["${postCreate}"]
    '';
  };
}

{inputs, ...}: {
  flake.modules.homeManager.worktrunk = {
    config,
    lib,
    pkgs,
    ...
  }: let
    wt = lib.getExe pkgs.worktrunk;
    herdr = lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    git = lib.getExe pkgs.git;
    jq = lib.getExe pkgs.jq;

    wtStart = pkgs.writeShellScript "wt-start" ''
      wt=${lib.escapeShellArg wt}
      herdr=${lib.escapeShellArg herdr}
      git=${lib.escapeShellArg git}
      jq=${lib.escapeShellArg jq}
      ${builtins.readFile ./scripts/wt-start.sh}
    '';

    wtRemove = pkgs.writeShellScript "wt-remove-herdr" ''
      herdr=${lib.escapeShellArg herdr}
      jq=${lib.escapeShellArg jq}
      ${builtins.readFile ./scripts/wt-remove.sh}
    '';

    wtRemoveGone = pkgs.writeShellScript "wt-remove-gone" ''
      wt=${lib.escapeShellArg wt}
      git=${lib.escapeShellArg git}
      jq=${lib.escapeShellArg jq}
      ${builtins.readFile ./scripts/wt-remove-gone.sh}
    '';
  in {
    options.my.worktrunk.worktreePath = lib.mkOption {
      type = lib.types.str;
      default = "~/.local/share/worktrees/{{ repo }}/{{ branch | sanitize_hash }}";
      description = "Worktrunk worktree path template.";
    };

    config = {
      home.packages = [
        pkgs.worktrunk
        pkgs.bash
        pkgs.fzf
        pkgs.git
        pkgs.jq
        (pkgs.runCommand "wt-start" {} "install -Dm755 ${wtStart} $out/bin/wt-start")
      ];

      xdg.configFile."worktrunk/config.toml".source = (pkgs.formats.toml {}).generate "worktrunk-config.toml" {
        worktree-path = config.my.worktrunk.worktreePath;
        post-remove.herdr = "${wtRemove} {{ worktree_path }}";
        aliases.remove-gone = "${wtRemoveGone} {{ args }}";
      };
    };
  };
}

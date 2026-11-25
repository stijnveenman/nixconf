{inputs, ...}: {
  flake.modules.homeManager.worktrunk = {
    config,
    lib,
    pkgs,
    ...
  }: let
    wt = lib.getExe pkgs.worktrunk;
    herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    herdr = lib.getExe herdrPackage;
    git = lib.getExe pkgs.git;
    jq = lib.getExe pkgs.jq;
    gum = lib.getExe pkgs.gum;

    wtStart = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.wt-start;

    wtRemove = pkgs.writeShellScript "wt-remove-herdr" ''
      herdr=${lib.escapeShellArg herdr}
      jq=${lib.escapeShellArg jq}
      ${builtins.readFile ./scripts/wt-remove.sh}
    '';

    wtSafeRemove = pkgs.writeShellScript "wt-safe-remove" ''
      wt=${lib.escapeShellArg wt}
      git=${lib.escapeShellArg git}
      gum=${lib.escapeShellArg gum}
      ${builtins.readFile ./scripts/wt-safe-remove.sh}
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

    options.my.worktrunk.safeRemove = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = wtSafeRemove;
      description = "Script removing the current worktree, confirming before forcing.";
    };

    config = {
      home.packages = [
        pkgs.worktrunk
        pkgs.bash
        pkgs.fzf
        pkgs.git
        pkgs.jq
        wtStart
      ];

      xdg.configFile."worktrunk/config.toml".source = (pkgs.formats.toml {}).generate "worktrunk-config.toml" {
        worktree-path = config.my.worktrunk.worktreePath;
        post-remove.herdr = "${wtRemove} {{ worktree_path }}";
        aliases.remove-gone = "${wtRemoveGone} {{ args }}";
      };
    };
  };
}

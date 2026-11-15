{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
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
      (pkgs.runCommand "wt-start" {} "install -Dm755 ${import ./scripts/wt-start.nix {inherit inputs lib pkgs;}} $out/bin/wt-start")
    ];

    xdg.configFile."worktrunk/config.toml".source = (pkgs.formats.toml {}).generate "worktrunk-config.toml" {
      worktree-path = config.my.worktrunk.worktreePath;
      post-remove.herdr = "${import ./scripts/wt-remove.nix {inherit inputs lib pkgs;}} {{ worktree_path }}";
      aliases.remove-gone = "${import ./scripts/wt-remove-gone.nix {inherit lib pkgs;}} {{ args }}";
    };
  };
}

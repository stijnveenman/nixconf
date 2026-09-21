{pkgs, ...}: {
  home.packages = [pkgs.tuicr];

  # tuicr reads this from $XDG_CONFIG_HOME/tuicr/config.toml.
  # These settings fit the Gruvbox/Ghostty, Neovim, and PR-review workflow.
  xdg.configFile."tuicr/config.toml".text = ''
    diff_view = "side-by-side"
    compact_folders = true
    show_pr_checks = true
    editor = "nvim"
    comment_vim = true
    scroll_offset = 5
    ignore_whitespace = true
    q_quits = true
    diff_watch_interval_ms = 1000

    comment_types = [
      { id = "question", label = "question", definition = "ask for clarification", color = "yellow" },
      { id = "issue", definition = "problems to fix", color = "red" },
      { id = "praise", definition = "positive feedback", color = "green" },
      { id = "nit", label = "nitpick", definition = "small optional tweaks", color = "blue" },
    ]

    [forge]
    comment_type_prefix = false

    [export]
    session_header = false
  '';
}

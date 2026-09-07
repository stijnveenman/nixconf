{bun}: {
  id = "treehouse.pool";
  name = "Treehouse Pool";
  version = "0.1.0";
  min_herdr_version = "0.8.2";
  description = "Open pooled Treehouse worktrees as Herdr workspaces";
  platforms = ["macos" "linux"];

  panes = [
    {
      id = "new";
      title = "New pooled workspace";
      placement = "popup";
      width = "50%";
      height = 14;
      command = [bun "new.ts"];
    }
    {
      id = "confirm-force";
      title = "Treehouse return failed";
      placement = "popup";
      width = "60%";
      height = 16;
      command = [bun "confirm-force.ts"];
    }
  ];

  events = [
    {
      on = "workspace.closed";
      command = [bun "close.ts"];
    }
  ];
}

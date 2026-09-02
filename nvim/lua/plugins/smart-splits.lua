return {
  {
    "mrjones2014/smart-splits.nvim",
    -- Not lazy: the herdr integration is more reliable when the plugin is
    -- loaded early (it sets up detection on startup, like the tmux/kitty flows).
    lazy = false,
    init = function()
      -- Tell smart-splits we're inside herdr before it loads (lazy env hint).
      vim.g.smart_splits_multiplexer_integration = "herdr"
    end,
    opts = {
      -- At a Neovim edge, hand off to the neighbouring herdr pane instead of
      -- wrapping within Neovim.
      at_edge = "stop",
    },
    keys = {
      -- Seamless move between Neovim splits and herdr panes.
      { "<C-h>", function() require("smart-splits").move_cursor_left() end, desc = "Move to left split/pane" },
      { "<C-j>", function() require("smart-splits").move_cursor_down() end, desc = "Move to below split/pane" },
      { "<C-k>", function() require("smart-splits").move_cursor_up() end, desc = "Move to above split/pane" },
      { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move to right split/pane" },
      -- Resize splits.
      { "<A-h>", function() require("smart-splits").resize_left() end, desc = "Resize split left" },
      { "<A-j>", function() require("smart-splits").resize_down() end, desc = "Resize split down" },
      { "<A-k>", function() require("smart-splits").resize_up() end, desc = "Resize split up" },
      { "<A-l>", function() require("smart-splits").resize_right() end, desc = "Resize split right" },
    },
  },
}

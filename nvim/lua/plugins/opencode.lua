return {
  {
    "nickjvandyke/opencode.nvim",
    version = "*", -- Latest stable release
    config = function()
      local opencode_cmd = "opencode --port"
      ---@type snacks.terminal.Opts
      local snacks_terminal_opts = {
        win = {
          position = "right",
          enter = true,
        },
      }

      ---@type opencode.Opts
      vim.g.opencode_opts = {
        server = {
          start = function()
            require("snacks.terminal").open(opencode_cmd, snacks_terminal_opts)
          end,
        },
      }

      -- Recommended/example keymaps
      -- stylua: ignore start
      vim.keymap.set({ "n", "x", "t" }, "<C-x>", function() require("snacks.terminal").toggle(opencode_cmd, snacks_terminal_opts) end, { desc = "Focus OpenCode" })
      vim.keymap.set({ "n", "x" }, "go",      function() return require("opencode").operator("@this ") end,         { desc = "Append range to OpenCode", expr = true })
      vim.keymap.set({ "n" },      "goo",     function() return require("opencode").operator("@this ") .. "_" end,  { desc = "Append line to OpenCode", expr = true })
      vim.keymap.set({ "n" },      "<S-C-u>", function() require("opencode").command("session.half.page.up") end,   { desc = "Scroll OpenCode up" })
      vim.keymap.set({ "n" },      "<S-C-d>", function() require("opencode").command("session.half.page.down") end, { desc = "Scroll OpenCode down" })
      -- stylua: ignore end

      -- Forward OpenCode events as `OpencodeEvent` autocmds
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:*",
        callback = function(args)
          ---@type opencode.server.Event
          local event = args.data.event

          if event.type == "session.status" and event.properties.status.type == "idle" then
            vim.notify("OpenCode prompt finished")
          end
        end,
      })
    end,
  },
}

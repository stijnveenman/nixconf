return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            -- Show hidden files in the current explorer folder.
            hidden = true,
            -- Keep the sidebar while switching focus, but close it after opening a file.
            auto_close = false,
            actions = {
              -- Copy selected paths relative to Neovim's working directory.
              explorer_yank_relative = function(picker)
                if vim.fn.mode():find("^[vV]") then
                  picker.list:select()
                end

                local cwd = vim.fn.getcwd()
                local paths = {}
                for _, item in ipairs(picker:selected({ fallback = true })) do
                  local path = Snacks.picker.util.path(item)
                  table.insert(paths, vim.fn.fnamemodify(path, ":."))
                end
                picker.list:set_selected()
                vim.fn.setreg(vim.v.register or "+", table.concat(paths, "\n"), "c")
                Snacks.notify.info("Yanked " .. #paths .. " paths relative to " .. cwd)
              end,
            },
            win = {
              list = {
                keys = {
                  ["y"] = { "explorer_yank_relative", mode = { "n", "x" } },
                },
              },
            },
            jump = { close = true },
            layout = {
              preset = "sidebar",
              preview = false,
              layout = { width = 60, min_width = 60 },
            },
          },
        },
      },
    },
  },
}

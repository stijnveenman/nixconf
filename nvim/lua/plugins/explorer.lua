return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            -- Keep the sidebar while switching focus, but close it after opening a file.
            auto_close = false,
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

return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            auto_close = true,
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

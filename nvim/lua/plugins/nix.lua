return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        nix = {},
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        nix = { "alejandra" },
      },
    },
  },
}

-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local Util = require("lazyvim.util")
vim.keymap.set({ "n", "t" }, "<C-g>", function()
  Snacks.terminal({ "lazygit" }, {
    id = "lazygit",
    toggle = true,
    cwd = Util.root(),
  })
end, { desc = "Lazygit (root dir)" })

-- move highlighted text around
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line up" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line down" })

vim.keymap.set("i", "jj", "<Esc>", { desc = "Escape insert mode" })

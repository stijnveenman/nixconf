-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local Util = require("lazyvim.util")
vim.keymap.set("n", "<C-g>", function()
  Snacks.terminal({ "lazygit" }, { cwd = Util.root(), esc_esc = false, ctrl_hjkl = false })
end, { desc = "Lazygit (root dir)" })

vim.keymap.set("n", "<C-c>", function()
  Snacks.terminal({ "opencode" }, { cwd = Util.root(), esc_esc = false, ctrl_hjkl = false })
end, { desc = "opencode (root dir)" })

-- move highlighted text around
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line up" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line down" })

vim.keymap.set("i", "jj", "<Esc>", { desc = "Escape insert mode" })

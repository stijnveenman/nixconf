-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- move highlighted text around
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line up" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line down" })

vim.keymap.set("i", "jj", "<Esc>", { desc = "Escape insert mode" })

-- Leave Ctrl-/ available for tmux's global popup binding.
for _, mode in ipairs({ "n", "t" }) do
  for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
    pcall(vim.keymap.del, mode, lhs)
  end
end

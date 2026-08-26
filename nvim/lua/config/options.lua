-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.snacks_animate = false

-- Always use the git worktree root (fall back to cwd) instead of the LSP's
-- own resolved root, so being inside e.g. nvim/ doesn't shrink the root dir.
vim.g.root_spec = { { ".git" }, "cwd" }

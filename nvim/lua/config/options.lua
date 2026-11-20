-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.snacks_animate = false

-- Sync yank/paste with the system clipboard everywhere. LazyVim leaves it off
-- over SSH.
vim.opt.clipboard = "unnamedplus"

-- Over SSH, copy through OSC 52. Herdr forwards OSC 52 writes to the local
-- terminal but does not answer clipboard reads, so paste returns the last
-- yank; paste from the local clipboard with the terminal's paste key.
if vim.env.SSH_CONNECTION then
  local osc52 = require("vim.ui.clipboard.osc52")
  local last = { {}, "v" }
  local function copy(reg)
    local write = osc52.copy(reg)
    return function(lines, regtype)
      last = { lines, regtype }
      write(lines, regtype)
    end
  end
  local function paste()
    return last
  end
  vim.g.clipboard = {
    name = "OSC 52 (copy only)",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end

-- Always use the git worktree root (fall back to cwd) instead of the LSP's
-- own resolved root, so being inside e.g. nvim/ doesn't shrink the root dir.
vim.g.root_spec = { { ".git" }, "cwd" }

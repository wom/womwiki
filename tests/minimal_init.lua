-- Minimal init for CI testing
-- Disable built-in plugins before setting runtimepath
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.cmd([[set packpath=/tmp/nvim/site]])

-- Add plugin to runtime path
local plugin_dir = vim.fn.getcwd()
vim.opt.rtp:append(plugin_dir)

-- Minimal config to suppress warnings
vim.g.womwiki_disable_mappings = true

-- Test bootstrap for mini.test
-- Separate from minimal_init.lua so existing smoke test is unaffected

-- Disable built-in plugins
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.womwiki_disable_mappings = true

-- Reset runtimepath and add plugin
vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Find mini.nvim
local function add_mini()
	local paths = {}
	if vim.env.MINI_PATH and vim.env.MINI_PATH ~= "" then
		table.insert(paths, vim.env.MINI_PATH)
	end
	local data_dir = vim.fn.stdpath("data")
	table.insert(paths, data_dir .. "/site/pack/deps/start/mini.nvim")
	table.insert(paths, data_dir .. "/site/pack/deps/opt/mini.nvim")

	for _, path in ipairs(paths) do
		if vim.uv.fs_stat(path) then
			vim.opt.rtp:append(path)
			return
		end
	end

	error("mini.nvim not found. Set MINI_PATH env var or install to " .. data_dir .. "/site/pack/deps/start/mini.nvim")
end

add_mini()

require("mini.test").setup({
	execute = {
		reporter = require("mini.test").gen_reporter.stdout({ group_depth = 2 }),
	},
})

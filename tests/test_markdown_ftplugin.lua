local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

local config = require("womwiki.config")
local plugin_dir = vim.fn.getcwd()

local state = {}

local T = new_set({
	hooks = {
		pre_case = function()
			state.old_config = config.config
			state.old_wikidir = config.wikidir
			state.old_dailydir = config.dailydir
			state.wiki_dir = vim.fn.tempname()
			vim.fn.mkdir(state.wiki_dir, "p")
			config.setup({ path = state.wiki_dir })
		end,
		after_case = function()
			config.config = state.old_config
			config.wikidir = state.old_wikidir
			config.dailydir = state.old_dailydir
			vim.fn.delete(state.wiki_dir, "rf")
		end,
	},
})

local function open_buffer(filepath)
	vim.fn.writefile({ "# Test" }, filepath)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.bo[buf].swapfile = false
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_name(buf, filepath)
	vim.b.womwiki = nil
	dofile(plugin_dir .. "/ftplugin/markdown.lua")
	return buf
end

local function has_buffer_map(buf, lhs)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if mapping.lhs == lhs then
			return true
		end
	end
	return false
end

T["installs Markdown mappings only inside the configured wiki"] = function()
	local wiki_file = state.wiki_dir .. "/note.md"
	local wiki_buf = open_buffer(wiki_file)
	expect.equality(has_buffer_map(wiki_buf, "gf"), true)
	expect.equality(has_buffer_map(wiki_buf, "  "), false)
	expect.equality(vim.b.womwiki, true)
	vim.api.nvim_buf_delete(wiki_buf, { force = true })

	local outside_file = vim.fn.tempname() .. ".md"
	local outside_buf = open_buffer(outside_file)
	expect.equality(has_buffer_map(outside_buf, "gf"), false)
	expect.equality(vim.b.womwiki, nil)
	expect.equality(vim.bo.omnifunc, "v:lua.require'womwiki'.link_complete")
	vim.api.nvim_buf_delete(outside_buf, { force = true })
	vim.fn.delete(outside_file)
end

return T

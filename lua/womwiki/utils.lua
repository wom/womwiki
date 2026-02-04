-- womwiki/utils.lua
-- Utility functions shared across modules

local config = require("womwiki.config")

local M = {}

-- Setup highlight groups for graph view
function M.setup_graph_highlights()
	vim.api.nvim_set_hl(0, "WomwikiGraphHeader", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "WomwikiGraphStats", { link = "Number", default = true })
	vim.api.nvim_set_hl(0, "WomwikiGraphHub", { link = "String", default = true })
	vim.api.nvim_set_hl(0, "WomwikiGraphOrphan", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "WomwikiGraphCurrent", { link = "Special", default = true })
	vim.api.nvim_set_hl(0, "WomwikiGraphKey", { link = "Keyword", default = true })
	vim.api.nvim_set_hl(0, "WomwikiGraphBorder", { link = "FloatBorder", default = true })
	vim.api.nvim_set_hl(0, "WomwikiTag", { link = "Identifier", default = true })
end

-- Detect available picker and return picker type + module
function M.get_picker()
	-- Use configured picker if available
	if config.config.picker == "telescope" then
		if pcall(require, "telescope") then
			return "telescope", require("telescope.builtin")
		end
		vim.notify("Configured picker 'telescope' is not installed", vim.log.levels.ERROR)
		return nil, nil
	elseif config.config.picker == "mini" then
		if pcall(require, "mini.pick") then
			return "mini", require("mini.pick")
		end
		vim.notify("Configured picker 'mini' is not installed", vim.log.levels.ERROR)
		return nil, nil
	elseif config.config.picker == "fzf" then
		if pcall(require, "fzf-lua") then
			return "fzf", require("fzf-lua")
		end
		vim.notify("Configured picker 'fzf' is not installed", vim.log.levels.ERROR)
		return nil, nil
	elseif config.config.picker == "snacks" then
		if pcall(require, "snacks") then
			return "snacks", require("snacks")
		end
		vim.notify("Configured picker 'snacks' is not installed", vim.log.levels.ERROR)
		return nil, nil
	end

	-- Auto-detect if no preference configured
	if pcall(require, "snacks") then
		return "snacks", require("snacks")
	elseif pcall(require, "fzf-lua") then
		return "fzf", require("fzf-lua")
	elseif pcall(require, "mini.pick") then
		return "mini", require("mini.pick")
	elseif pcall(require, "telescope") then
		return "telescope", require("telescope.builtin")
	else
		vim.notify(
			"No picker installed. Please install one of: snacks, fzf-lua, mini.pick, or telescope.nvim",
			vim.log.levels.ERROR
		)
		return nil, nil
	end
end

-- Ensure filename has .md extension
function M.ensure_md_extension(filename)
	if not filename:match("%.md$") then
		return filename .. ".md"
	end
	return filename
end

-- Open a file in wiki context
function M.open_wiki_file(path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	vim.b.womwiki = true
	vim.cmd("lcd " .. vim.fn.fnameescape(config.wikidir))
end

-- Initialize highlights on module load
M.setup_graph_highlights()

return M

-- womwiki/utils.lua
-- Utility functions shared across modules

local config = require("womwiki.config")

local M = {}

--- Setup highlight groups for graph view and tags
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

--- Detect available picker and return picker type + module
--- @return string|nil picker_type One of "snacks", "fzf", "mini", "telescope"
--- @return table|nil picker_module The picker's Lua module
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

--- Ensure filename has .md extension
--- @param filename string Filename to check
--- @return string Filename with .md extension
function M.ensure_md_extension(filename)
	if not filename:match("%.md$") then
		return filename .. ".md"
	end
	return filename
end

--- Open a file in wiki context (sets lcd and womwiki buffer flag)
--- @param path string Path to the wiki file
function M.open_wiki_file(path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	vim.b.womwiki = true
	vim.cmd("lcd " .. vim.fn.fnameescape(config.wikidir))
end

--- Select an item from a string list using the available picker
--- @param items string[] List of string items to display
--- @param opts table Options: { title = "Prompt Title" }
--- @param on_select function Callback with the selected string
function M.picker_select(items, opts, on_select)
	local picker_type, picker = M.get_picker()
	if not picker_type then
		vim.ui.select(items, { prompt = opts.title }, function(selected)
			if selected then
				on_select(selected)
			end
		end)
		return
	end

	if picker_type == "telescope" then
		require("telescope.pickers")
			.new({}, {
				prompt_title = opts.title,
				finder = require("telescope.finders").new_table({
					results = items,
				}),
				sorter = require("telescope.config").values.generic_sorter({}),
				attach_mappings = function(_, map)
					map("i", "<CR>", function(prompt_bufnr)
						local selection = require("telescope.actions.state").get_selected_entry()
						require("telescope.actions").close(prompt_bufnr)
						if selection then
							on_select(selection.value)
						end
					end)
					return true
				end,
			})
			:find()
	elseif picker_type == "mini" then
		picker.start({
			source = { items = items, name = opts.title },
			choose = function(item)
				on_select(item)
			end,
		})
	elseif picker_type == "snacks" then
		picker.picker.select(items, {
			prompt = opts.title,
		}, function(selected)
			if selected then
				local value = type(selected) == "table" and selected.text or selected
				on_select(value)
			end
		end)
	elseif picker_type == "fzf" then
		picker.fzf_exec(items, {
			prompt = opts.title .. "> ",
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						on_select(selected[1])
					end
				end,
			},
		})
	end
end

--- Live grep using the available picker
--- @param opts table Options: { cwd = "/path", search = "pattern" (optional), title = "Title" (optional) }
function M.picker_grep(opts)
	local picker_type, picker = M.get_picker()
	if not picker_type then
		vim.notify("womwiki: No picker available for search", vim.log.levels.ERROR)
		return
	end

	if picker_type == "telescope" then
		if opts.search then
			picker.grep_string({
				search = opts.search,
				cwd = opts.cwd,
				use_regex = true,
				prompt_title = opts.title,
			})
		else
			picker.live_grep({ cwd = opts.cwd })
		end
	elseif picker_type == "mini" then
		picker.builtin.grep_live({}, { source = { cwd = opts.cwd } })
	elseif picker_type == "snacks" then
		if opts.search then
			picker.picker.grep({
				search = opts.search,
				cwd = opts.cwd,
			})
		else
			picker.picker.grep({ cwd = opts.cwd })
		end
	elseif picker_type == "fzf" then
		if opts.search then
			picker.grep({
				search = opts.search,
				cwd = opts.cwd,
				no_esc = true,
			})
		else
			picker.live_grep({ cwd = opts.cwd })
		end
	end
end

--- Read entire file contents
--- @param path string Absolute path to file
--- @return string|nil content File contents or nil on failure
--- @return string|nil err Error message on failure
function M.read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil, "Failed to open: " .. path
	end
	local content = file:read("*a")
	file:close()
	return content
end

--- Read file as array of lines
--- @param path string Absolute path to file
--- @return string[]|nil lines Array of lines or nil on failure
--- @return string|nil err Error message on failure
function M.read_lines(path)
	local file = io.open(path, "r")
	if not file then
		return nil, "Failed to open: " .. path
	end
	local lines = {}
	for line in file:lines() do
		lines[#lines + 1] = line
	end
	file:close()
	return lines
end

--- Write content to file (overwrites)
--- @param path string Absolute path to file
--- @param content string Content to write
--- @return boolean success
--- @return string|nil err Error message on failure
function M.write_file(path, content)
	local file = io.open(path, "w")
	if not file then
		return false, "Failed to write: " .. path
	end
	file:write(content)
	file:close()
	return true
end

--- Append content to file
--- @param path string Absolute path to file
--- @param content string Content to append
--- @return boolean success
--- @return string|nil err Error message on failure
function M.append_file(path, content)
	local file = io.open(path, "a")
	if not file then
		return false, "Failed to append: " .. path
	end
	file:write(content)
	file:close()
	return true
end

-- Initialize highlights on module load
M.setup_graph_highlights()

return M

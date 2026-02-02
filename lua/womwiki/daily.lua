-- womwiki/daily.lua
-- Daily notes functionality: open, close, cleanup, templates

local config = require("womwiki.config")

local M = {}

-- Built-in default template for daily notes
M.DEFAULT_TEMPLATE = [[# {{ date }}
## Standup
* Vibe:
* ToDone:
* ToDo:
* Blocking:
## Log
]]

-- Get daily template path with fallback logic
-- Priority: 1. Wiki template, 2. Config template, 3. Built-in default
function M.get_template_path()
	-- Check wiki template first
	local wiki_template = config.wikidir .. "/.templates/daily.md"
	local file = io.open(vim.fn.expand(wiki_template), "r")
	if file then
		file:close()
		return wiki_template, "wiki"
	end

	-- Check user config template
	local config_template = os.getenv("HOME") .. "/.config/nvim/templates/daily.templ"
	file = io.open(config_template, "r")
	if file then
		file:close()
		return config_template, "config"
	end

	-- Use built-in default
	return nil, "builtin"
end

-- Get daily template content
function M.get_template_content()
	local template_path, source = M.get_template_path()

	if source == "builtin" then
		return M.DEFAULT_TEMPLATE
	end

	local file = io.open(template_path, "r")
	if not file then
		vim.notify("Failed to read template: " .. template_path, vim.log.levels.ERROR)
		return M.DEFAULT_TEMPLATE
	end

	local content = file:read("*a")
	file:close()
	return content
end

-- List all files in the daily directory
function M.list_files()
	local files = {}
	local handle = vim.uv.fs_scandir(config.dailydir)
	if handle then
		while true do
			local name, type = vim.uv.fs_scandir_next(handle)
			if not name then
				break
			end
			if type == "file" then
				table.insert(files, name)
			end
		end
	end
	return files
end

-- Open or create a daily file with a specified offset in days
function M.open(days_offset)
	days_offset = days_offset or 0
	local date = os.date("%Y-%m-%d", os.time() + days_offset * 86400)
	local filename = config.dailydir .. "/" .. date .. ".md"

	-- Expand ~ and other path components for io.open() compatibility
	local expanded_filename = vim.fn.expand(filename)

	-- Check if the file exists
	local file = io.open(expanded_filename, "r")
	if file then
		file:close()
	else
		-- File doesn't exist, create it with the template content
		local template_content = M.get_template_content()
		local content = template_content:gsub("{{ date }}", date)

		file = io.open(expanded_filename, "w")
		if not file then
			vim.notify("Failed to create daily file: " .. expanded_filename, vim.log.levels.ERROR)
			return
		end
		file:write(content)
		file:close()
	end

	-- Open the file in the editor with 20% height or minimum 10 lines
	vim.cmd("aboveleft " .. math.max(10, math.floor(vim.o.lines * 0.2)) .. "split " .. filename)
	vim.b.womwiki = true -- Tag the buffer as a womwiki buffer
	vim.cmd("lcd " .. vim.fn.fnameescape(config.wikidir)) -- Set wikidir just for that buffer
end

-- Close daily note buffer
function M.close()
	if vim.b.womwiki then
		vim.cmd("quit") -- Close the window and buffer
	else
		vim.notify("Not a womwiki buffer", vim.log.levels.WARN)
	end
end

-- Edit daily template
function M.edit_template()
	local utils = require("womwiki.utils")

	-- Always use/create wiki template
	local wiki_template = config.wikidir .. "/.templates/daily.md"
	local template_dir = config.wikidir .. "/.templates"
	local expanded_path = vim.fn.expand(wiki_template)

	-- Check if wiki template already exists
	local file = io.open(expanded_path, "r")
	if file then
		file:close()
		-- Template exists, just open it
		utils.open_wiki_file(wiki_template)
		return
	end

	-- Wiki template doesn't exist - create it
	vim.fn.mkdir(vim.fn.expand(template_dir), "p")

	-- Check if config template exists to copy from
	local _, source = M.get_template_path()
	local content

	if source == "config" then
		-- Copy from config template
		content = M.get_template_content()
		vim.notify("Migrating config template to wiki template", vim.log.levels.INFO)
	else
		-- Use built-in default
		content = M.DEFAULT_TEMPLATE
		vim.notify("Created wiki template from built-in default", vim.log.levels.INFO)
	end

	-- Write template to file
	file = io.open(expanded_path, "w")
	if not file then
		vim.notify("Failed to create template file: " .. wiki_template, vim.log.levels.ERROR)
		return
	end
	file:write(content)
	file:close()

	-- Open the template file
	utils.open_wiki_file(wiki_template)
end

-- Cleanup unmodified daily notes
function M.cleanup()
	local template_content = M.get_template_content()

	local files = M.list_files()
	local unmodified_files = {}

	for _, filename in ipairs(files) do
		local filepath = config.dailydir .. "/" .. filename
		local year, month, day = filename:match("(%d+)-(%d+)-(%d+)%.md")

		if year and month and day then
			local date = string.format("%04d-%02d-%02d", tonumber(year), tonumber(month), tonumber(day))

			-- Generate expected content from template
			local expected_content = template_content:gsub("{{ date }}", date)

			-- Read actual file content
			local file = io.open(filepath, "r")
			if file then
				local actual_content = file:read("*a")
				file:close()

				-- Compare content
				if actual_content == expected_content then
					table.insert(unmodified_files, {
						name = filename,
						path = filepath,
						date = date,
					})
				end
			end
		end
	end

	if #unmodified_files == 0 then
		vim.notify("No unmodified daily notes found!", vim.log.levels.INFO)
		return
	end

	-- Show preview of files to be deleted
	local preview_lines = { "Found " .. #unmodified_files .. " unmodified daily note(s):", "" }
	for _, file in ipairs(unmodified_files) do
		table.insert(preview_lines, "  " .. file.name)
	end
	table.insert(preview_lines, "")
	table.insert(preview_lines, "Press 'd' to delete all, 'q' to cancel")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"

	local width = 50
	local height = math.min(#preview_lines, 20)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.ceil((vim.o.columns - width) / 2),
		row = math.ceil((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
	})

	local keymap_opts = { buffer = buf, nowait = true, silent = true }

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
		vim.notify("Cleanup cancelled", vim.log.levels.INFO)
	end, keymap_opts)

	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
		vim.notify("Cleanup cancelled", vim.log.levels.INFO)
	end, keymap_opts)

	vim.keymap.set("n", "d", function()
		local deleted_count = 0
		for _, file in ipairs(unmodified_files) do
			local success = os.remove(file.path)
			if success then
				deleted_count = deleted_count + 1
			else
				vim.notify("Failed to delete: " .. file.name, vim.log.levels.WARN)
			end
		end

		vim.api.nvim_win_close(win, true)
		vim.notify("Deleted " .. deleted_count .. " unmodified daily note(s)", vim.log.levels.INFO)
	end, keymap_opts)
end

return M

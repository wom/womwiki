-- womwiki/daily.lua
-- Daily notes functionality: open, close, cleanup, templates

local config = require("womwiki.config")

local M = {}

-- Built-in default template for daily notes
M.DEFAULT_TEMPLATE = [[<!-- [« Prev](prev) | [Next »](next) -->
# {{ date }}
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

-- Get the date from current buffer's filename (assumes YYYY-MM-DD.md format)
local function get_current_daily_date()
	local filename = vim.fn.expand("%:t")
	local year, month, day = filename:match("(%d%d%d%d)-(%d%d)-(%d%d)%.md$")
	if year and month and day then
		return string.format("%04d-%02d-%02d", tonumber(year), tonumber(month), tonumber(day))
	end
	return nil
end

-- Get adjacent daily note (prev or next existing one)
-- direction: -1 for prev, 1 for next
function M.get_adjacent_daily(direction)
	local current_date = get_current_daily_date()
	if not current_date then
		vim.notify("Not in a daily note", vim.log.levels.WARN)
		return nil
	end

	-- Get all daily files and sort them
	local files = M.list_files()
	local dates = {}
	for _, f in ipairs(files) do
		local date = f:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$")
		if date then
			table.insert(dates, date)
		end
	end
	table.sort(dates)

	-- Find current date's position
	local current_idx = nil
	for i, d in ipairs(dates) do
		if d == current_date then
			current_idx = i
			break
		end
	end

	if not current_idx then
		return nil
	end

	-- Get adjacent
	local target_idx = current_idx + direction
	if target_idx < 1 or target_idx > #dates then
		return nil
	end

	return dates[target_idx]
end

-- Navigate to previous daily note
function M.prev()
	local target_date = M.get_adjacent_daily(-1)
	if target_date then
		local filepath = config.dailydir .. "/" .. target_date .. ".md"
		vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		M.setup_daily_buffer()
	else
		vim.notify("No previous daily note", vim.log.levels.INFO)
	end
end

-- Navigate to next daily note
function M.next()
	local target_date = M.get_adjacent_daily(1)
	if target_date then
		local filepath = config.dailydir .. "/" .. target_date .. ".md"
		vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		M.setup_daily_buffer()
	else
		vim.notify("No next daily note", vim.log.levels.INFO)
	end
end

-- Handle navigation when pressing Enter on nav line
function M.handle_nav_line()
	local line = vim.api.nvim_get_current_line()
	local col = vim.fn.col(".")

	-- Check if we're on the nav line (contains Prev and Next)
	if not (line:match("Prev") and line:match("Next")) then
		-- Not on nav line, do normal Enter
		return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
	end

	-- Find positions of Prev and Next in the line
	local prev_start, prev_end = line:find("Prev")
	local next_start, next_end = line:find("Next")

	if prev_start and col >= prev_start and col <= prev_end then
		M.prev()
	elseif next_start and col >= next_start and col <= next_end then
		M.next()
	else
		-- Cursor not on Prev or Next, default to prev if before middle, next if after
		local mid = #line / 2
		if col < mid then
			M.prev()
		else
			M.next()
		end
	end
end

-- Setup buffer-local keymaps for daily notes
function M.setup_daily_buffer()
	vim.b.womwiki = true
	vim.cmd("lcd " .. vim.fn.fnameescape(config.wikidir))

	local opts = { buffer = true, silent = true }
	vim.keymap.set("n", "[w", M.prev, vim.tbl_extend("force", opts, { desc = "Previous daily note" }))
	vim.keymap.set("n", "]w", M.next, vim.tbl_extend("force", opts, { desc = "Next daily note" }))
	vim.keymap.set("n", "<CR>", M.handle_nav_line, vim.tbl_extend("force", opts, { desc = "Daily nav or normal Enter" }))
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
	M.setup_daily_buffer()
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

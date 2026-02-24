-- womwiki/daily.lua
-- Daily notes functionality: open, close, cleanup, templates

local config = require("womwiki.config")

local M = {}

-- Built-in default template for daily notes
M.DEFAULT_TEMPLATE = [=[<!-- [[« Prev]] · [[Next »]] -->
# {{ date }}
## Standup
* Vibe:
* ToDone:
* ToDo:
* Blocking:
## Log
]=]

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

-- Find the most recent existing daily before a given date
function M.get_most_recent_previous_daily(reference_date)
	local files = M.list_files()
	local dates = {}
	for _, f in ipairs(files) do
		local date = f:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$")
		if date then
			table.insert(dates, date)
		end
	end
	table.sort(dates)

	-- Find the most recent date before reference_date
	local target_date = nil
	for _, date in ipairs(dates) do
		if date < reference_date then
			target_date = date  -- Keep updating to get the most recent one before reference_date
		else
			break  -- Since sorted, we won't find any more before reference_date
		end
	end

	return target_date
end

-- Extract incomplete todos from a daily note file
function M.extract_incomplete_todos(filepath)
	local todos = {}
	local file = io.open(filepath, "r")
	if not file then
		return todos
	end

	for line in file:lines() do
		-- Match lines with [ ] (unchecked) or [-] (blocked/in progress)
		if line:match("^%s*%-(%s+)%[%s%]") or line:match("^%s*%-(%s+)%[%-]") then
			table.insert(todos, line)
		end
	end

	file:close()
	return todos
end

-- Mark forwarded todos in a file (change [ ] or [-] to [>])
function M.mark_todos_forwarded(filepath, todo_lines_to_mark)
	local file = io.open(filepath, "r")
	if not file then
		return false
	end

	-- Read all lines
	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	-- Create a set of todos to mark (strip leading/trailing whitespace for comparison)
	local todos_to_mark = {}
	for _, todo in ipairs(todo_lines_to_mark) do
		-- Normalize: strip leading/trailing whitespace, keep only the content
		local normalized = todo:gsub("^%s+", ""):gsub("%s+$", "")
		todos_to_mark[normalized] = true
	end

	-- Update lines
	for i, line in ipairs(lines) do
		local normalized = line:gsub("^%s+", ""):gsub("%s+$", "")
		if todos_to_mark[normalized] then
			-- Replace the checkbox with [>], preserving original spacing
			lines[i] = line:gsub("%[%s%]", "[>]"):gsub("%[%-]", "[>]")
		end
	end

	-- Write back
	file = io.open(filepath, "w")
	if not file then
		return false
	end
	for _, line in ipairs(lines) do
		file:write(line .. "\n")
	end
	file:close()

	return true
end

-- Setup buffer-local keymaps for daily notes
function M.setup_daily_buffer()
	vim.b.womwiki = true
	vim.cmd("lcd " .. vim.fn.fnameescape(config.wikidir))

	local opts = { buffer = true, silent = true }
	vim.keymap.set("n", "[w", M.prev, vim.tbl_extend("force", opts, { desc = "Previous daily note" }))
	vim.keymap.set("n", "]w", M.next, vim.tbl_extend("force", opts, { desc = "Next daily note" }))
	-- Note: <CR> link following is handled by ftplugin/markdown.lua
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
	local is_new_file = false
	if file then
		file:close()
	else
		is_new_file = true
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

		-- If this is a new file, check for incomplete todos from most recent previous daily
		local prev_date = M.get_most_recent_previous_daily(date)
		if prev_date then
			local prev_filepath = config.dailydir .. "/" .. prev_date .. ".md"
			local todos = M.extract_incomplete_todos(prev_filepath)

			if #todos > 0 then
				-- Append rollover section to new file
				file = io.open(expanded_filename, "a")
				if file then
					file:write("\n## Rolled over from [[" .. prev_date .. "]]\n\n")
					for _, todo in ipairs(todos) do
						file:write(todo .. "\n")
					end
					file:close()

					-- Mark todos as forwarded in previous file
					M.mark_todos_forwarded(prev_filepath, todos)
				end
			end
		end
	end

	-- Open the file in the editor
	-- If actively editing a file, use split; otherwise use full screen
	local should_split = vim.fn.bufname() ~= "" and vim.bo.buftype == "" and vim.fn.line("$") > 1

	if should_split then
		-- Split view: 20% height or minimum 10 lines
		vim.cmd("aboveleft " .. math.max(10, math.floor(vim.o.lines * 0.2)) .. "split " .. filename)
	else
		-- Full screen: we're on splash/empty buffer, open in current window
		vim.cmd("edit " .. filename)
	end
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

-- Patterns for nav line detection
local NAV_PATTERNS = {
	-- New wikilink format: <!-- [[« Prev]] · [[Next »]] -->
	new = "^<!%-%- %[%[« Prev%]%] · %[%[Next »%]%] %-%->",
	-- Old markdown link format: <!-- [« Prev](prev) | [Next »](next) -->
	old = "^<!%-%- %[« Prev%]%(prev%) | %[Next »%]%(next%) %-%->",
}

-- New nav line content
local NEW_NAV_LINE = "<!-- [[« Prev]] · [[Next »]] -->"

-- Modernize daily note headers to use new nav format
function M.modernize_headers()
	local files = M.list_files()
	local to_update = {}
	local skipped = 0

	for _, filename in ipairs(files) do
		local date = filename:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$")
		if date then
			local filepath = config.dailydir .. "/" .. filename
			local file = io.open(filepath, "r")
			if file then
				local first_line = file:read("*l")
				local rest = file:read("*a")
				file:close()

				if first_line then
					if first_line:match(NAV_PATTERNS.new) then
						-- Already has new format, skip
					elseif first_line:match(NAV_PATTERNS.old) then
						-- Old format, needs update
						table.insert(to_update, {
							name = filename,
							path = filepath,
							action = "replace",
							rest = rest,
						})
					elseif first_line:match("^# " .. date .. "$") then
						-- Missing nav line, date heading on line 1
						table.insert(to_update, {
							name = filename,
							path = filepath,
							action = "prepend",
							first_line = first_line,
							rest = rest,
						})
					else
						-- Ambiguous format, skip
						skipped = skipped + 1
					end
				end
			end
		end
	end

	if #to_update == 0 then
		local msg = "All daily notes already have modern headers!"
		if skipped > 0 then
			msg = msg .. " (" .. skipped .. " skipped due to ambiguous format)"
		end
		vim.notify(msg, vim.log.levels.INFO)
		return
	end

	-- Show preview of files to be updated
	local preview_lines = { "Found " .. #to_update .. " daily note(s) to modernize:", "" }
	for _, file in ipairs(to_update) do
		local action_label = file.action == "replace" and "update" or "add nav"
		table.insert(preview_lines, "  " .. file.name .. " (" .. action_label .. ")")
	end
	if skipped > 0 then
		table.insert(preview_lines, "")
		table.insert(preview_lines, "  (" .. skipped .. " files skipped - ambiguous format)")
	end
	table.insert(preview_lines, "")
	table.insert(preview_lines, "Press 'm' to modernize, 'q' to cancel")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"

	local width = 55
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

	local function close_cancel()
		vim.api.nvim_win_close(win, true)
		vim.notify("Modernize cancelled", vim.log.levels.INFO)
	end

	vim.keymap.set("n", "q", close_cancel, keymap_opts)
	vim.keymap.set("n", "<Esc>", close_cancel, keymap_opts)

	vim.keymap.set("n", "m", function()
		local updated_count = 0
		for _, file in ipairs(to_update) do
			local new_content
			if file.action == "replace" then
				-- Replace old nav line with new
				new_content = NEW_NAV_LINE .. "\n" .. (file.rest or "")
			else
				-- Prepend nav line before existing content
				new_content = NEW_NAV_LINE .. "\n" .. file.first_line .. "\n" .. (file.rest or "")
			end

			local f = io.open(file.path, "w")
			if f then
				f:write(new_content)
				f:close()
				updated_count = updated_count + 1
			else
				vim.notify("Failed to write: " .. file.name, vim.log.levels.WARN)
			end
		end

		vim.api.nvim_win_close(win, true)
		vim.notify("Modernized " .. updated_count .. " daily note(s)", vim.log.levels.INFO)
	end, keymap_opts)
end

return M

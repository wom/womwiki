local M = {}

M.version = "0.0.1"

M.config = {
	path = os.getenv("HOME") .. "/src/wiki",
	picker = nil, -- Optional: 'telescope', 'mini', 'fzf', 'snacks'
}

local function update_paths()
	local symlink_path = vim.fn.expand(M.config.path)
	M.wikidir = vim.uv.fs_realpath(symlink_path) or symlink_path
	M.dailydir = M.wikidir .. "/daily"
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	update_paths()
end

-- Initialize with defaults
update_paths()

-- Built-in default template for daily notes
local DEFAULT_DAILY_TEMPLATE = [[# {{ date }}
## Standup
* Vibe:
* ToDone:
* ToDo:
* Blocking:
## Log
]]

-- Helper: Get daily template path with fallback logic
-- Priority: 1. Wiki template, 2. Config template, 3. Built-in default
local function get_daily_template_path()
	-- Check wiki template first
	local wiki_template = M.wikidir .. "/.templates/daily.md"
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

-- Helper: Get daily template content
local function get_daily_template_content()
	local template_path, source = get_daily_template_path()

	if source == "builtin" then
		return DEFAULT_DAILY_TEMPLATE
	end

	local file = io.open(template_path, "r")
	if not file then
		vim.notify("Failed to read template: " .. template_path, vim.log.levels.ERROR)
		return DEFAULT_DAILY_TEMPLATE
	end

	local content = file:read("*a")
	file:close()
	return content
end

-- Helper: Detect available picker and return picker type + module
local function get_picker()
	-- Use configured picker if available
	if M.config.picker == "telescope" then
		if pcall(require, "telescope") then
			return "telescope", require("telescope.builtin")
		end
		vim.notify("Configured picker 'telescope' is not installed", vim.log.levels.ERROR)
		return nil, nil
	elseif M.config.picker == "mini" then
		if pcall(require, "mini.pick") then
			return "mini", require("mini.pick")
		end
		vim.notify("Configured picker 'mini' is not installed", vim.log.levels.ERROR)
		return nil, nil
	elseif M.config.picker == "fzf" then
		if pcall(require, "fzf-lua") then
			return "fzf", require("fzf-lua")
		end
		vim.notify("Configured picker 'fzf' is not installed", vim.log.levels.ERROR)
		return nil, nil
	elseif M.config.picker == "snacks" then
		if pcall(require, "snacks") then
			return "snacks", require("snacks")
		end
		vim.notify("Configured picker 'snacks' is not installed", vim.log.levels.ERROR)
		return nil, nil
	end

	-- Auto-detect if no preference configured
	-- Check for snacks (modern, feature-rich)
	if pcall(require, "snacks") then
		return "snacks", require("snacks")
	-- Check for fzf-lua (fast, feature-rich)
	elseif pcall(require, "fzf-lua") then
		return "fzf", require("fzf-lua")
	-- Check for mini.pick (lightweight, modern)
	elseif pcall(require, "mini.pick") then
		return "mini", require("mini.pick")
	-- Check for telescope (most popular)
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

-- Helper: Ensure filename has .md extension
local function ensure_md_extension(filename)
	if not filename:match("%.md$") then
		return filename .. ".md"
	end
	return filename
end

-- Helper: Open a file in wiki context
local function open_wiki_file(path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	vim.b.womwiki = true
	vim.cmd("lcd " .. vim.fn.fnameescape(M.wikidir))
end

-- List all files in the daily directory
function M.list_files()
	local files = {}
	local handle = vim.uv.fs_scandir(M.dailydir)
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

-- Print a greeting and list all files in the daily directory
function M.hello()
	local _ = M.list_files()
end

-- Open picker to find files in the wiki directory
function M.wiki()
	local picker_type, picker = get_picker()
	if not picker then
		return
	end

	if picker_type == "telescope" then
		picker.find_files({ cwd = M.wikidir, hidden = false })
	elseif picker_type == "mini" then
		picker.builtin.files({}, { source = { cwd = M.wikidir } })
	elseif picker_type == "snacks" then
		picker.picker.files({ cwd = M.wikidir })
	elseif picker_type == "fzf" then
		picker.files({ cwd = M.wikidir })
	end
end

-- Open picker to find files in the daily directory
function M.dailies()
	local picker_type, picker = get_picker()
	if not picker then
		return
	end

	-- Ensure dailydir is set
	if not M.dailydir or M.dailydir == "" then
		vim.notify("Daily directory not configured", vim.log.levels.ERROR)
		return
	end

	if picker_type == "telescope" then
		picker.find_files({ cwd = M.dailydir, hidden = false })
	elseif picker_type == "mini" then
		picker.builtin.files({}, { source = { cwd = M.dailydir } })
	elseif picker_type == "snacks" then
		picker.picker.files({ cwd = M.dailydir })
	elseif picker_type == "fzf" then
		picker.files({ cwd = M.dailydir })
	end
end

-- Get list of subdirectories in wiki directory
function M.get_wiki_folders()
	local folders = { M.wikidir } -- Always include root wiki directory
	local handle = vim.uv.fs_scandir(M.wikidir)
	if handle then
		while true do
			local name, type = vim.uv.fs_scandir_next(handle)
			if not name then
				break
			end
			if type == "directory" then
				table.insert(folders, M.wikidir .. "/" .. name)
			end
		end
	end
	return folders
end

-- Create a new wiki file
function M.create_file()
	local folders = M.get_wiki_folders()
	local folder_names = {}
	for _, folder in ipairs(folders) do
		if folder == M.wikidir then
			table.insert(folder_names, "/ (root)")
		else
			table.insert(folder_names, folder:match(".*/(.*)"))
		end
	end

	vim.ui.select(folder_names, {
		prompt = "Select folder:",
	}, function(choice_name, choice_index)
		if choice_name then
			local selected_folder = folders[choice_index]
			vim.ui.input({
				prompt = "Enter filename (without .md extension): ",
				default = "",
			}, function(filename)
				if filename and filename ~= "" then
					filename = ensure_md_extension(filename)
					local full_path = selected_folder .. "/" .. filename

					-- Check if file already exists
					local file = io.open(full_path, "r")
					if file then
						file:close()
						-- File exists, just open it
						open_wiki_file(full_path)
					else
						-- Create new file
						local new_file = io.open(full_path, "w")
						if new_file then
							new_file:write("# " .. filename:gsub("%.md$", "") .. "\n\n")
							new_file:close()
							open_wiki_file(full_path)
						else
							vim.notify("Failed to create file: " .. full_path, vim.log.levels.ERROR)
						end
					end
				end
			end)
		end
	end)
end

-- Open recent wiki files using available picker
function M.recent()
	local picker_type, picker = get_picker()
	if not picker then
		return
	end

	-- Get all oldfiles and filter them manually
	local oldfiles = vim.v.oldfiles or {}
	local wiki_files = {}

	for _, file in ipairs(oldfiles) do
		-- Expand tilde in file path for comparison
		local expanded_file = vim.fn.expand(file)
		-- Check if file starts with wiki directory path (plain string match)
		if vim.startswith(expanded_file, M.wikidir) then
			table.insert(wiki_files, file)
		end
	end

	if #wiki_files == 0 then
		vim.notify("No recent wiki files found", vim.log.levels.INFO)
		return
	end

	if picker_type == "telescope" then
		require("telescope.pickers")
			.new({}, {
				prompt_title = "Recent Wiki Files",
				finder = require("telescope.finders").new_table({
					results = wiki_files,
				}),
				sorter = require("telescope.config").values.generic_sorter({}),
				attach_mappings = function(_, map)
					map("i", "<CR>", function(prompt_bufnr)
						local selection = require("telescope.actions.state").get_selected_entry()
						require("telescope.actions").close(prompt_bufnr)
						if selection then
							open_wiki_file(selection.value)
						end
					end)
					return true
				end,
			})
			:find()
	elseif picker_type == "mini" then
		picker.start({
			source = { items = wiki_files, name = "Recent Wiki Files" },
			choose = function(item)
				open_wiki_file(item)
			end,
		})
	elseif picker_type == "snacks" then
		picker.picker.pick({
			source = wiki_files,
			prompt = "Recent Wiki Files",
			format = function(item)
				return item
			end,
			confirm = function(item)
				open_wiki_file(item)
			end,
		})
	elseif picker_type == "fzf" then
		picker.fzf_exec(wiki_files, {
			prompt = "Recent Wiki Files> ",
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						open_wiki_file(selected[1])
					end
				end,
			},
			fzf_opts = { ["--sort"] = true },
		})
	end
end

-- Search through wiki files using available picker
function M.search()
	local picker_type, picker = get_picker()
	if not picker then
		return
	end

	if picker_type == "telescope" then
		picker.live_grep({ cwd = M.wikidir })
	elseif picker_type == "mini" then
		-- Note: mini.pick doesn't have live_grep built-in, using grep builtin instead
		picker.builtin.grep_live({}, { source = { cwd = M.wikidir } })
	elseif picker_type == "snacks" then
		picker.picker.grep({ cwd = M.wikidir })
	elseif picker_type == "fzf" then
		picker.live_grep({ cwd = M.wikidir })
	end
end

-- Open or create a daily file with a specified offset in days
function M.open_daily(days_offset)
	days_offset = days_offset or 0
	local date = os.date("%Y-%m-%d", os.time() + days_offset * 86400)
	local filename = M.dailydir .. "/" .. date .. ".md"

	-- Expand ~ and other path components for io.open() compatibility
	local expanded_filename = vim.fn.expand(filename)

	-- Check if the file exists
	local file = io.open(expanded_filename, "r")
	if file then
		file:close()
	else
		-- File doesn't exist, create it with the template content
		local template_content = get_daily_template_content()
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
	vim.cmd("lcd " .. vim.fn.fnameescape(M.wikidir)) -- Set wikidir just for that buffer
end

function M.close_daily()
	if vim.b.womwiki then
		vim.cmd("quit") -- Close the window and buffer
	else
		vim.notify("Not a womwiki buffer", vim.log.levels.WARN)
	end
end

-- Calendar view for navigating daily notes
function M.calendar()
	local current_year = tonumber(os.date("%Y"))
	local current_month = tonumber(os.date("%m"))
	local current_day = tonumber(os.date("%d"))

	local function days_in_month(year, month)
		return os.date("*t", os.time({ year = year, month = month + 1, day = 0 })).day
	end

	local function first_day_of_month(year, month)
		return os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
	end

	local function get_existing_dailies()
		local dailies = {}
		local files = M.list_files()
		for _, file in ipairs(files) do
			local year, month, day = file:match("(%d+)-(%d+)-(%d+)%.md")
			if year and month and day then
				local key = string.format("%04d-%02d-%02d", tonumber(year), tonumber(month), tonumber(day))
				dailies[key] = true
			end
		end
		return dailies
	end

	local function show_calendar(year, month, selected_day)
		-- Cache existing dailies once instead of on every render
		local existing_dailies = get_existing_dailies()

		local function render_calendar(yr, mon, sel_day)
			local lines = {}

			table.insert(
				lines,
				string.format("     %s %d", os.date("%B", os.time({ year = yr, month = mon, day = 1 })), yr)
			)
			table.insert(lines, "")
			table.insert(lines, " Su Mo Tu We Th Fr Sa")

			local days = days_in_month(yr, mon)
			local first_day = first_day_of_month(yr, mon)

			local line = ""
			for _ = 1, first_day - 1 do
				line = line .. "   "
			end

			for day = 1, days do
				local date_key = string.format("%04d-%02d-%02d", yr, mon, day)
				local has_note = existing_dailies[date_key]

				local day_str
				if day == sel_day then
					day_str = string.format("[%2d]", day)
				elseif day == current_day and mon == current_month and yr == current_year then
					day_str = string.format("<%2d>", day)
				elseif has_note then
					day_str = string.format("*%2d ", day)
				else
					day_str = string.format(" %2d ", day)
				end

				line = line .. day_str

				if (first_day - 1 + day) % 7 == 0 then
					table.insert(lines, line)
					line = ""
				end
			end

			if line ~= "" then
				table.insert(lines, line)
			end

			table.insert(lines, "")
			table.insert(lines, "Navigate: hjkl/arrows | Enter: open | q: quit")
			table.insert(lines, "n: next month | p: prev month | t: today")
			table.insert(lines, "Legend: <today> [selected] *has-note")

			return lines
		end

		local lines = render_calendar(year, month, selected_day)

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.bo[buf].buftype = "nofile"

		local width = 30
		local height = #lines
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			col = math.ceil((vim.o.columns - width) / 2),
			row = math.ceil((vim.o.lines - height) / 2),
			style = "minimal",
			border = "rounded",
		})

		local function update_display()
			local new_lines = render_calendar(year, month, selected_day)
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
			vim.bo[buf].modifiable = false
		end

		local function open_selected()
			local offset = os.difftime(
				os.time({ year = year, month = month, day = selected_day }),
				os.time({ year = current_year, month = current_month, day = current_day })
			) / 86400
			vim.api.nvim_win_close(win, true)
			M.open_daily(math.floor(offset))
		end

		local keymap_opts = { buffer = buf, nowait = true, silent = true }

		vim.keymap.set("n", "q", function()
			vim.api.nvim_win_close(win, true)
		end, keymap_opts)
		vim.keymap.set("n", "<Esc>", function()
			vim.api.nvim_win_close(win, true)
		end, keymap_opts)
		vim.keymap.set("n", "<CR>", open_selected, keymap_opts)

		vim.keymap.set("n", "h", function()
			selected_day = math.max(1, selected_day - 1)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "<Left>", function()
			selected_day = math.max(1, selected_day - 1)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "l", function()
			selected_day = math.min(days_in_month(year, month), selected_day + 1)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "<Right>", function()
			selected_day = math.min(days_in_month(year, month), selected_day + 1)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "k", function()
			selected_day = math.max(1, selected_day - 7)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "<Up>", function()
			selected_day = math.max(1, selected_day - 7)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "j", function()
			selected_day = math.min(days_in_month(year, month), selected_day + 7)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "<Down>", function()
			selected_day = math.min(days_in_month(year, month), selected_day + 7)
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "n", function()
			month = month + 1
			if month > 12 then
				month = 1
				year = year + 1
			end
			selected_day = math.min(selected_day, days_in_month(year, month))
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "p", function()
			month = month - 1
			if month < 1 then
				month = 12
				year = year - 1
			end
			selected_day = math.min(selected_day, days_in_month(year, month))
			update_display()
		end, keymap_opts)

		vim.keymap.set("n", "t", function()
			year = current_year
			month = current_month
			selected_day = current_day
			update_display()
		end, keymap_opts)
	end

	show_calendar(current_year, current_month, current_day)
end

-- Cleanup unmodified daily notes
function M.cleanup()
	local template_content = get_daily_template_content()

	local files = M.list_files()
	local unmodified_files = {}

	for _, filename in ipairs(files) do
		local filepath = M.dailydir .. "/" .. filename
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

-- Submenu for Browse & Search operations
function M.browse_and_search_menu()
	M.show_menu({
		{ "Browse All Notes", M.wiki },
		{ "Browse Dailies", M.dailies },
		{ "Search Dailies", M.dailies },
		{
			"Yesterday",
			function()
				M.open_daily(-1)
			end,
		},
	}, "Browse & Search", M.picker)
end

-- Submenu for Analysis operations
function M.analyze_menu()
	M.show_menu({
		{ "Backlinks", M.backlinks },
		{ "Graph View", M.show_graph },
	}, "Analyze", M.picker)
end

-- Submenu for Settings/Tools
function M.settings_menu()
	M.show_menu({
		{ "Edit Daily Template", M.edit_daily_template },
		{ "Cleanup Empty Dailies", M.cleanup },
	}, "Settings/Tools", M.picker)
end

-- Edit daily template
function M.edit_daily_template()
	-- Always use/create wiki template
	local wiki_template = M.wikidir .. "/.templates/daily.md"
	local template_dir = M.wikidir .. "/.templates"
	local expanded_path = vim.fn.expand(wiki_template)

	-- Check if wiki template already exists
	local file = io.open(expanded_path, "r")
	if file then
		file:close()
		-- Template exists, just open it
		open_wiki_file(wiki_template)
		return
	end

	-- Wiki template doesn't exist - create it
	vim.fn.mkdir(vim.fn.expand(template_dir), "p")

	-- Check if config template exists to copy from
	local _, source = get_daily_template_path()
	local content

	if source == "config" then
		-- Copy from config template
		content = get_daily_template_content()
		vim.notify("Migrating config template to wiki template", vim.log.levels.INFO)
	else
		-- Use built-in default
		content = DEFAULT_DAILY_TEMPLATE
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
	open_wiki_file(wiki_template)
end

-- Helper to check if current buffer is today's daily note
local function is_today_daily_open()
	if not vim.b.womwiki then
		return false
	end
	local today = os.date("%Y-%m-%d")
	local current_file = vim.fn.expand("%:t:r")
	return current_file == today
end

-- Main menu choices (dynamically generated)
local function get_main_choices()
	local choices = {}

	-- Smart Today/Close Daily toggle
	if is_today_daily_open() then
		table.insert(choices, { "Close Daily", M.close_daily })
	else
		table.insert(choices, {
			"Today",
			function()
				M.open_daily()
			end,
		})
	end

	table.insert(choices, { "Recent", M.recent })
	table.insert(choices, { "Calendar", M.calendar })
	table.insert(choices, { "Search", M.search })
	table.insert(choices, { "Create", M.create_file })
	table.insert(choices, { "---", nil })
	table.insert(choices, { "Browse & Search >", M.browse_and_search_menu })
	table.insert(choices, { "Analyze >", M.analyze_menu })
	table.insert(choices, { "Settings/Tools >", M.settings_menu })

	return choices
end

-- Generic menu display function
function M.show_menu(choices, title, back_func)
	title = title or "womwiki"
	local options = { title }
	for i, choice in ipairs(choices) do
		table.insert(options, string.format("%d: %s", i, choice[1]))
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, options)

	local max_width = 0
	for _, line in ipairs(options) do
		if #line > max_width then
			max_width = #line
		end
	end

	local height = #options
	local win_width = math.min(max_width + 4, vim.api.nvim_get_option("columns"))
	local win_height = math.min(height, vim.api.nvim_get_option("lines"))
	local row = math.ceil((vim.api.nvim_get_option("lines") - win_height) / 2)
	local col = math.ceil((vim.api.nvim_get_option("columns") - win_width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = win_width,
		height = win_height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
	})

	local function execute_choice(index)
		if index and choices[index] and choices[index][2] then
			vim.api.nvim_win_close(win, true)
			choices[index][2]()
		end
	end

	local function handle_enter()
		local line = vim.api.nvim_get_current_line()
		local index = tonumber(line:match("^(%d):"))
		execute_choice(index)
	end

	local function handle_back()
		vim.api.nvim_win_close(win, true)
		if back_func then
			back_func()
		end
	end

	vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
		noremap = true,
		silent = true,
		callback = handle_enter,
	})

	-- q and Esc behave differently based on whether we have a back function
	if back_func then
		-- In submenu: Esc and 0 go back, q closes completely
		vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
			noremap = true,
			silent = true,
			callback = function()
				vim.api.nvim_win_close(win, true)
			end,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
			noremap = true,
			silent = true,
			callback = handle_back,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "0", "", {
			noremap = true,
			silent = true,
			callback = handle_back,
		})
	else
		-- In main menu: q and Esc close
		vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
			noremap = true,
			silent = true,
			callback = function()
				vim.api.nvim_win_close(win, true)
			end,
		})
		vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
			noremap = true,
			silent = true,
			callback = function()
				vim.api.nvim_win_close(win, true)
			end,
		})
	end

	for i = 1, math.min(#choices, 9) do
		vim.api.nvim_buf_set_keymap(buf, "n", tostring(i), "", {
			noremap = true,
			silent = true,
			callback = function()
				execute_choice(i)
			end,
		})
	end
end

-- Get all markdown links from a file
local function get_links_from_file(file_path)
	local links = {}
	local file = io.open(file_path, "r")
	if not file then
		return links
	end

	for line in file:lines() do
		-- Match [text](link) pattern
		for _, link in line:gmatch("%[([^%]]+)%]%(([^%)]+)%)") do
			-- Skip URLs, only process local links
			if not link:match("^https?://") then
				-- Remove .md extension if present for consistency
				local clean_link = link:gsub("%.md$", "")
				table.insert(links, clean_link)
			end
		end
	end
	file:close()
	return links
end

-- Get all wiki files (excluding daily directory)
local function get_all_wiki_files()
	local files = {}
	local function scan_directory(dir, relative_path)
		local handle = vim.uv.fs_scandir(dir)
		if not handle then
			return
		end

		while true do
			local name, type = vim.uv.fs_scandir_next(handle)
			if not name then
				break
			end

			local full_path = dir .. "/" .. name
			local file_relative = relative_path and (relative_path .. "/" .. name) or name

			if type == "file" and name:match("%.md$") then
				table.insert(files, {
					name = name:gsub("%.md$", ""), -- remove extension
					path = full_path,
					relative = file_relative,
				})
			elseif type == "directory" and name ~= "daily" and name ~= ".git" then
				scan_directory(full_path, file_relative)
			end
		end
	end

	scan_directory(M.wikidir)
	return files
end

-- Show backlinks to current file
function M.backlinks()
	local current_file = vim.fn.expand("%:t:r")
	if current_file == "" then
		vim.notify("Not in a wiki file", vim.log.levels.WARN)
		return
	end

	local picker_type, picker = get_picker()
	if not picker then
		return
	end

	-- Search for files that link to current file
	local search_patterns = {
		"\\]\\(" .. current_file .. "\\)", -- [text](filename)
		"\\]\\(" .. current_file .. "\\.md\\)", -- [text](filename.md)
	}

	if picker_type == "telescope" then
		picker.grep_string({
			search = table.concat(search_patterns, "|"),
			cwd = M.wikidir,
			use_regex = true,
			prompt_title = "󰌷 Backlinks to: " .. current_file .. ".md",
		})
	elseif picker_type == "mini" then
		-- For mini.pick, we'll use a simpler approach
		picker.builtin.grep_live({
			default_text = current_file,
		}, { source = { cwd = M.wikidir } })
	elseif picker_type == "snacks" then
		picker.picker.grep({
			search = table.concat(search_patterns, "|"),
			cwd = M.wikidir,
		})
	elseif picker_type == "fzf" then
		picker.grep({
			search = table.concat(search_patterns, "|"),
			cwd = M.wikidir,
			fzf_opts = {
				["--header"] = "󰌷 Backlinks to: " .. current_file .. ".md",
				["--preview"] = "bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || cat {1}",
				["--preview-window"] = "right:60%",
			},
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						-- Extract filename from "filename:line:content" format
						local file = selected[1]:match("^([^:]+)")
						if file then
							open_wiki_file(M.wikidir .. "/" .. file)
						end
					end
				end,
			},
		})
	end
end

-- Build link graph data structure
local function build_link_graph()
	local files = get_all_wiki_files()
	local graph = {}
	local all_targets = {}

	-- Initialize graph and collect all possible targets
	for _, file in ipairs(files) do
		graph[file.name] = {
			path = file.path,
			links_to = {},
			linked_from = {},
		}
		all_targets[file.name] = true
	end

	-- Build adjacency lists
	for _, file in ipairs(files) do
		local links = get_links_from_file(file.path)
		for _, target in ipairs(links) do
			-- Only include links to files that exist
			if all_targets[target] then
				table.insert(graph[file.name].links_to, target)
				if graph[target] then
					table.insert(graph[target].linked_from, file.name)
				end
			end
		end
	end

	return graph
end

-- Create ASCII art graph visualization
function M.show_graph()
	local graph = build_link_graph()
	local current_file = vim.fn.expand("%:t:r")

	-- Build graph display
	local lines = {}
	local max_width = 60

	-- Header
	table.insert(lines, "╭─ Wiki Link Graph " .. string.rep("─", max_width - 18) .. "╮")
	if current_file ~= "" then
		table.insert(lines, "│ Current: " .. current_file .. string.rep(" ", max_width - 10 - #current_file) .. "│")
	end
	table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")

	-- Calculate stats
	local total_files = 0
	local total_links = 0
	local orphans = {}
	local hubs = {}

	for name, data in pairs(graph) do
		total_files = total_files + 1
		total_links = total_links + #data.links_to

		-- Find orphans (no incoming links)
		if #data.linked_from == 0 then
			table.insert(orphans, name)
		end

		-- Find hubs (many incoming links)
		if #data.linked_from >= 3 then
			table.insert(hubs, { name = name, count = #data.linked_from })
		end
	end

	-- Sort hubs by link count
	table.sort(hubs, function(a, b)
		return a.count > b.count
	end)

	-- Stats section
	table.insert(
		lines,
		"│ Files: "
			.. total_files
			.. " | Links: "
			.. total_links
			.. " | Orphans: "
			.. #orphans
			.. string.rep(" ", max_width - 30 - #tostring(total_files) - #tostring(total_links) - #tostring(#orphans))
			.. "│"
	)
	table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")

	-- Current file details (if in a wiki file)
	if current_file ~= "" and graph[current_file] then
		local data = graph[current_file]
		table.insert(lines, "│ Current file connections:" .. string.rep(" ", max_width - 25) .. "│")

		if #data.links_to > 0 then
			table.insert(
				lines,
				"│   → Links to: "
					.. table.concat(data.links_to, ", ")
					.. string.rep(" ", math.max(0, max_width - 14 - #table.concat(data.links_to, ", ")))
					.. "│"
			)
		else
			table.insert(lines, "│   → Links to: (none)" .. string.rep(" ", max_width - 19) .. "│")
		end

		if #data.linked_from > 0 then
			table.insert(
				lines,
				"│   ← Linked from: "
					.. table.concat(data.linked_from, ", ")
					.. string.rep(" ", math.max(0, max_width - 17 - #table.concat(data.linked_from, ", ")))
					.. "│"
			)
		else
			table.insert(lines, "│   ← Linked from: (none)" .. string.rep(" ", max_width - 22) .. "│")
		end

		table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
	end

	-- Top hubs
	if #hubs > 0 then
		table.insert(lines, "│ Popular files (most backlinks):" .. string.rep(" ", max_width - 32) .. "│")
		for i = 1, math.min(5, #hubs) do
			local hub = hubs[i]
			local line = "│   " .. hub.name .. " (" .. hub.count .. ")"
			table.insert(lines, line .. string.rep(" ", max_width - #line + 1) .. "│")
		end
		table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
	end

	-- Orphan files
	if #orphans > 0 then
		table.insert(lines, "│ Orphan files (no backlinks):" .. string.rep(" ", max_width - 29) .. "│")
		local orphan_text = table.concat(orphans, ", ")
		local words = vim.split(orphan_text, ", ")
		local current_line = "│   "

		for _, word in ipairs(words) do
			if #current_line + #word + 2 > max_width - 1 then
				table.insert(lines, current_line .. string.rep(" ", max_width - #current_line + 1) .. "│")
				current_line = "│   " .. word
			else
				if current_line ~= "│   " then
					current_line = current_line .. ", " .. word
				else
					current_line = current_line .. word
				end
			end
		end
		if current_line ~= "│   " then
			table.insert(lines, current_line .. string.rep(" ", max_width - #current_line + 1) .. "│")
		end
		table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
	end

	-- Instructions
	table.insert(lines, "│ Press 'b' for backlinks | 'o' for orphans | 'h' for hubs │")
	table.insert(lines, "│ Press 'f' to find file  | 'q' to quit                   │")
	table.insert(lines, "╰" .. string.rep("─", max_width) .. "╯")

	-- Display in floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"

	local width = max_width + 2
	local height = math.min(#lines, vim.o.lines - 4)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Wiki Graph ",
		title_pos = "center",
	})

	local keymap_opts = { buffer = buf, nowait = true, silent = true }

	-- Keybindings
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, keymap_opts)

	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, keymap_opts)

	vim.keymap.set("n", "b", function()
		vim.api.nvim_win_close(win, true)
		M.backlinks()
	end, keymap_opts)

	vim.keymap.set("n", "f", function()
		vim.api.nvim_win_close(win, true)
		M.wiki()
	end, keymap_opts)

	vim.keymap.set("n", "h", function()
		vim.api.nvim_win_close(win, true)
		-- Show hubs in picker
		local picker_type, picker = get_picker()
		if picker and #hubs > 0 then
			local hub_items = {}
			for _, hub in ipairs(hubs) do
				table.insert(hub_items, hub.name .. ".md")
			end

			if picker_type == "telescope" then
				require("telescope.pickers")
					.new({}, {
						prompt_title = "Hub Files",
						finder = require("telescope.finders").new_table({
							results = hub_items,
						}),
						sorter = require("telescope.config").values.generic_sorter({}),
						attach_mappings = function(_, map)
							map("i", "<CR>", function(prompt_bufnr)
								local selection = require("telescope.actions.state").get_selected_entry()
								require("telescope.actions").close(prompt_bufnr)
								if selection then
									open_wiki_file(M.wikidir .. "/" .. selection.value)
								end
							end)
							return true
						end,
					})
					:find()
			elseif picker_type == "mini" then
				picker.start({
					source = { items = hub_items, name = "Hub Files" },
					choose = function(item)
						open_wiki_file(M.wikidir .. "/" .. item)
					end,
				})
			elseif picker_type == "snacks" then
				picker.picker.pick({
					source = hub_items,
					prompt = "Hub Files",
					format = function(item)
						return item
					end,
					confirm = function(item)
						open_wiki_file(M.wikidir .. "/" .. item)
					end,
				})
			elseif picker_type == "fzf" then
				picker.fzf_exec(hub_items, {
					prompt = "Hub Files> ",
					actions = {
						["default"] = function(selected)
							if selected and selected[1] then
								local filename = selected[1]
								open_wiki_file(M.wikidir .. "/" .. filename)
							end
						end,
					},
				})
			end
		end
	end, keymap_opts)

	vim.keymap.set("n", "o", function()
		vim.api.nvim_win_close(win, true)
		-- Show orphans in picker
		local picker_type, picker = get_picker()
		if picker and #orphans > 0 then
			local orphan_items = {}
			for _, orphan in ipairs(orphans) do
				table.insert(orphan_items, orphan .. ".md")
			end

			if picker_type == "telescope" then
				require("telescope.pickers")
					.new({}, {
						prompt_title = "Orphan Files",
						finder = require("telescope.finders").new_table({
							results = orphan_items,
						}),
						sorter = require("telescope.config").values.generic_sorter({}),
						attach_mappings = function(_, map)
							map("i", "<CR>", function(prompt_bufnr)
								local selection = require("telescope.actions.state").get_selected_entry()
								require("telescope.actions").close(prompt_bufnr)
								if selection then
									open_wiki_file(M.wikidir .. "/" .. selection.value)
								end
							end)
							return true
						end,
					})
					:find()
			elseif picker_type == "mini" then
				picker.start({
					source = { items = orphan_items, name = "Orphan Files" },
					choose = function(item)
						open_wiki_file(M.wikidir .. "/" .. item)
					end,
				})
			elseif picker_type == "snacks" then
				picker.picker.pick({
					source = orphan_items,
					prompt = "Orphan Files",
					format = function(item)
						return item
					end,
					confirm = function(item)
						open_wiki_file(M.wikidir .. "/" .. item)
					end,
				})
			elseif picker_type == "fzf" then
				picker.fzf_exec(orphan_items, {
					prompt = "Orphan Files> ",
					actions = {
						["default"] = function(selected)
							if selected and selected[1] then
								local filename = selected[1]
								open_wiki_file(M.wikidir .. "/" .. filename)
							end
						end,
					},
				})
			end
		end
	end, keymap_opts)
end

-- Main picker entry point
function M.picker()
	M.show_menu(get_main_choices(), "womwiki")
end

return M

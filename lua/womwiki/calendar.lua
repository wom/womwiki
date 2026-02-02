-- womwiki/calendar.lua
-- Interactive calendar view for navigating daily notes

local config = require("womwiki.config")
local daily = require("womwiki.daily")

local M = {}

-- Show calendar popup for navigating daily notes
function M.show()
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
		local files = daily.list_files()
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
			daily.open(math.floor(offset))
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

return M

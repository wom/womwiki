-- womwiki/capture.lua
-- Inbox and quick capture functionality

local config = require("womwiki.config")
local utils = require("womwiki.utils")

local M = {}

-- Get current buffer location as markdown link [file:line](path#Lline)
local function get_location_link()
	local bufname = vim.fn.expand("%:p")
	if bufname == "" or vim.bo[0].buftype ~= "" then
		return nil
	end

	local line = vim.fn.line(".")
	local filename = vim.fn.expand("%:t")

	-- Always use absolute path so links work from anywhere
	return string.format("[%s:%d](%s#L%d)", filename, line, bufname, line)
end

--- Format a capture entry from text and config options
--- @param text string The captured text
--- @param inbox_config table Inbox config with format and datetime_format fields
--- @return string Formatted entry string
function M._format_entry(text, inbox_config)
	local datetime = os.date(inbox_config.datetime_format)
	-- Escape % in replacement strings for gsub
	local safe_datetime = datetime:gsub("%%", "%%%%")
	local safe_text = text:gsub("%%", "%%%%")
	return inbox_config.format:gsub("{{ datetime }}", safe_datetime):gsub("{{ text }}", safe_text)
end

--- Append entry to inbox file, creating with header if needed
--- @param entry string Formatted entry to append
--- @param expanded_path string Expanded absolute path to the inbox file
--- @return boolean success
--- @return string|nil err Error message on failure
function M._append_to_inbox(entry, expanded_path)
	-- Check if file already exists
	local exists = io.open(expanded_path, "r")
	if exists then
		exists:close()
		local ok = utils.append_file(expanded_path, entry .. "\n")
		if not ok then
			return false, "Failed to open inbox"
		end
	else
		local ok =
			utils.write_file(expanded_path, "# Inbox\n\nQuick captures and fleeting thoughts.\n\n" .. entry .. "\n")
		if not ok then
			return false, "Failed to create inbox"
		end
	end
	return true
end

--- Quick capture: append a thought to inbox without leaving current context
--- @param text string|nil Text to capture (prompts interactively if nil)
--- @param include_location boolean|nil Whether to append source location link
function M.capture(text, include_location)
	local inbox_path = config.wikidir .. "/" .. config.config.inbox.file
	local expanded_path = vim.fn.expand(inbox_path)

	-- If text provided directly, use it; otherwise prompt
	if text and text ~= "" then
		local entry = M._format_entry(text, config.config.inbox)

		-- Append location link if requested
		if include_location then
			local location = get_location_link()
			if location then
				entry = entry .. " " .. location
			end
		end

		-- Append to inbox file
		local ok, err = M._append_to_inbox(entry, expanded_path)
		if not ok then
			vim.notify(err .. ": " .. inbox_path, vim.log.levels.ERROR)
			return
		end
		vim.notify("📥 Captured to inbox", vim.log.levels.INFO)
	else
		-- Prompt for input - capture location now before async prompt
		local location = include_location and get_location_link() or nil
		local prompt = location and "📥 Capture (+ location): " or "📥 Quick capture: "
		vim.ui.input({ prompt = prompt }, function(input)
			if input and input ~= "" then
				local entry = M._format_entry(input, config.config.inbox)
				if location then
					entry = entry .. " " .. location
				end

				local ok, err = M._append_to_inbox(entry, expanded_path)
				if not ok then
					vim.notify(err .. ": " .. inbox_path, vim.log.levels.ERROR)
					return
				end
				vim.notify("📥 Captured to inbox" .. (location and " (with location)" or ""), vim.log.levels.INFO)
			end
		end)
	end
end

--- Capture with current buffer location included
--- @param text string|nil Text to capture (prompts interactively if nil)
function M.capture_with_location(text)
	M.capture(text, true)
end

--- Capture visual selection to inbox (always includes location)
function M.capture_visual()
	-- Get visual selection
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.fn.getregion(start_pos, end_pos)
	local text = table.concat(lines, " ")

	if text and text ~= "" then
		M.capture(text, true) -- Visual capture always includes location
	else
		vim.notify("No text selected", vim.log.levels.WARN)
	end
end

--- Open inbox file for review/processing
function M.inbox()
	local inbox_path = config.wikidir .. "/" .. config.config.inbox.file
	local expanded_path = vim.fn.expand(inbox_path)

	-- Check if inbox exists, create if not
	local file = io.open(expanded_path, "r")
	if not file then
		if not utils.write_file(expanded_path, "# Inbox\n\nQuick captures and fleeting thoughts.\n\n") then
			vim.notify("Failed to create inbox: " .. inbox_path, vim.log.levels.ERROR)
			return
		end
		vim.notify("Created new inbox file", vim.log.levels.INFO)
	else
		file:close()
	end

	utils.open_wiki_file(inbox_path)
end

return M

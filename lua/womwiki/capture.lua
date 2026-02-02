-- womwiki/capture.lua
-- Inbox and quick capture functionality

local config = require("womwiki.config")
local utils = require("womwiki.utils")

local M = {}

-- Get current buffer location as markdown link [file:line](path#Lline)
local function get_location_link()
	local bufname = vim.fn.expand("%:p")
	if bufname == "" or vim.bo.buftype ~= "" then
		return nil
	end

	local line = vim.fn.line(".")
	local filename = vim.fn.expand("%:t")

	-- Always use absolute path so links work from anywhere
	return string.format("[%s:%d](%s#L%d)", filename, line, bufname, line)
end

-- Quick Capture: append a thought to inbox without leaving current context
function M.capture(text, include_location)
	local inbox_path = config.wikidir .. "/" .. config.config.inbox.file
	local expanded_path = vim.fn.expand(inbox_path)

	-- If text provided directly, use it; otherwise prompt
	if text and text ~= "" then
		local datetime = os.date(config.config.inbox.datetime_format)
		local entry = config.config.inbox.format:gsub("{{ datetime }}", datetime):gsub("{{ text }}", text)

		-- Append location link if requested
		if include_location then
			local location = get_location_link()
			if location then
				entry = entry .. " " .. location
			end
		end

		-- Append to inbox file
		local file = io.open(expanded_path, "a")
		if not file then
			-- File doesn't exist, create with header
			file = io.open(expanded_path, "w")
			if not file then
				vim.notify("Failed to create inbox: " .. inbox_path, vim.log.levels.ERROR)
				return
			end
			file:write("# Inbox\n\nQuick captures and fleeting thoughts.\n\n")
		end
		file:write(entry .. "\n")
		file:close()
		vim.notify("📥 Captured to inbox", vim.log.levels.INFO)
	else
		-- Prompt for input - capture location now before async prompt
		local location = include_location and get_location_link() or nil
		local prompt = location and "📥 Capture (+ location): " or "📥 Quick capture: "
		vim.ui.input({ prompt = prompt }, function(input)
			if input and input ~= "" then
				local datetime = os.date(config.config.inbox.datetime_format)
				local entry = config.config.inbox.format:gsub("{{ datetime }}", datetime):gsub("{{ text }}", input)
				if location then
					entry = entry .. " " .. location
				end

				local file = io.open(expanded_path, "a")
				if not file then
					file = io.open(expanded_path, "w")
					if not file then
						vim.notify("Failed to create inbox: " .. inbox_path, vim.log.levels.ERROR)
						return
					end
					file:write("# Inbox\n\nQuick captures and fleeting thoughts.\n\n")
				end
				file:write(entry .. "\n")
				file:close()
				vim.notify("📥 Captured to inbox" .. (location and " (with location)" or ""), vim.log.levels.INFO)
			end
		end)
	end
end

-- Capture with current buffer location
function M.capture_with_location(text)
	M.capture(text, true)
end

-- Capture visual selection (always includes location)
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

-- Open inbox file for review/processing
function M.inbox()
	local inbox_path = config.wikidir .. "/" .. config.config.inbox.file
	local expanded_path = vim.fn.expand(inbox_path)

	-- Check if inbox exists, create if not
	local file = io.open(expanded_path, "r")
	if not file then
		file = io.open(expanded_path, "w")
		if not file then
			vim.notify("Failed to create inbox: " .. inbox_path, vim.log.levels.ERROR)
			return
		end
		file:write("# Inbox\n\nQuick captures and fleeting thoughts.\n\n")
		file:close()
		vim.notify("Created new inbox file", vim.log.levels.INFO)
	else
		file:close()
	end

	utils.open_wiki_file(inbox_path)
end

return M

-- womwiki/init.lua
-- Main entry point - re-exports all modules for backward compatibility
-- This thin module provides the public API surface

local M = {}

M.version = "0.0.2"

-- Load all submodules
local config = require("womwiki.config")
local utils = require("womwiki.utils")
local daily = require("womwiki.daily")
local calendar = require("womwiki.calendar")
local capture = require("womwiki.capture")
local files = require("womwiki.files")
local menu = require("womwiki.menu")
local graph = require("womwiki.graph")

--------------------------------------------------------------------------------
-- Configuration (re-export from config module)
--------------------------------------------------------------------------------

M.config = config.config
M.wikidir = config.wikidir
M.dailydir = config.dailydir

function M.setup(opts)
	config.setup(opts)
	-- Update our re-exported references
	M.config = config.config
	M.wikidir = config.wikidir
	M.dailydir = config.dailydir
	-- Setup highlights
	utils.setup_graph_highlights()
end

--------------------------------------------------------------------------------
-- Daily Notes (re-export from daily module)
--------------------------------------------------------------------------------

M.open_daily = daily.open
M.close_daily = daily.close
M.list_files = daily.list_files
M.edit_daily_template = daily.edit_template
M.cleanup = daily.cleanup
M.daily_prev = daily.prev
M.daily_next = daily.next

--------------------------------------------------------------------------------
-- Calendar (re-export from calendar module)
--------------------------------------------------------------------------------

M.calendar = calendar.show

--------------------------------------------------------------------------------
-- Capture (re-export from capture module)
--------------------------------------------------------------------------------

M.capture = capture.capture
M.capture_with_location = capture.capture_with_location
M.capture_visual = capture.capture_visual
M.inbox = capture.inbox

--------------------------------------------------------------------------------
-- Files (re-export from files module)
--------------------------------------------------------------------------------

M.wiki = files.wiki
M.dailies = files.dailies
M.recent = files.recent
M.search = files.search
M.create_file = files.create
M.get_wiki_folders = files.get_wiki_folders
M.get_wiki_files = files.get_wiki_files
M.get_file_headings = files.get_file_headings

--------------------------------------------------------------------------------
-- Graph (re-export from graph module)
--------------------------------------------------------------------------------

M.backlinks = graph.backlinks
M.show_graph = graph.show

--------------------------------------------------------------------------------
-- Completion (link autocompletion)
--------------------------------------------------------------------------------

function M.link_complete(findstart, base)
	if findstart == 1 then
		local line = vim.fn.getline(".")
		local col = vim.fn.col(".") - 1
		local link_pos = line:sub(1, col):find("%]%([^)]*$")
		if link_pos then
			return link_pos + 1
		end
		return -3
	else
		local items = {}
		local wiki_files = files.get_wiki_files()
		local file_part, heading_part = base:match("^(.-)#(.*)$")

		if file_part and config.config.completion.include_headings then
			local target_file = nil
			for _, file in ipairs(wiki_files) do
				if file.path == file_part or file.path == file_part .. ".md" then
					target_file = file.full_path
					break
				end
			end

			if target_file then
				local headings = files.get_file_headings(target_file)
				for _, heading in ipairs(headings) do
					local word = file_part .. "#" .. heading.slug
					if word:lower():find(base:lower(), 1, true) or heading.text:lower():find((heading_part or ""):lower(), 1, true) then
						table.insert(items, {
							word = word,
							menu = heading.text,
							kind = "H" .. heading.level,
						})
					end
				end
			end
		else
			for _, file in ipairs(wiki_files) do
				if file.path:lower():find(base:lower(), 1, true) or file.title:lower():find(base:lower(), 1, true) then
					table.insert(items, {
						word = file.path,
						menu = file.title,
						kind = "F",
					})
					if #items >= config.config.completion.max_results then
						break
					end
				end
			end
		end

		return items
	end
end

function M.setup_completion()
	if not config.config.completion.enabled then
		return
	end
	vim.bo.omnifunc = "v:lua.require'womwiki'.link_complete"

	local has_cmp, cmp = pcall(require, "cmp")
	if has_cmp then
		local has_source, cmp_womwiki = pcall(require, "cmp_womwiki")
		if has_source then
			cmp.register_source("womwiki", cmp_womwiki.new())
		end
	end
end

--------------------------------------------------------------------------------
-- Menus
--------------------------------------------------------------------------------

M.show_menu = menu.show

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

	if is_today_daily_open() then
		table.insert(choices, { "Close [D]aily", "d", M.close_daily })
	else
		table.insert(choices, { "[T]oday", "t", function() M.open_daily() end })
	end

	table.insert(choices, { "[Q]uick Capture", "q", M.capture })
	table.insert(choices, { "[R]ecent", "r", M.recent })
	table.insert(choices, { "[C]alendar", "c", M.calendar })
	table.insert(choices, { "[S]earch", "s", M.search })
	table.insert(choices, { "Cr[e]ate", "e", M.create_file })
	table.insert(choices, { "---" })
	table.insert(choices, { "[A]nalyze >", "a", M.analyze_menu })
	table.insert(choices, { "Too[l]s >", "l", M.tools_menu })

	return choices
end

-- Browse & Search submenu
function M.browse_and_search_menu()
	M.show_menu({
		{ "Browse [A]ll Notes", "a", M.wiki },
		{ "Browse [D]ailies", "d", M.dailies },
		{ "[Y]esterday", "y", function() M.open_daily(-1) end },
	}, "Browse & Search", M.picker)
end

-- Analysis submenu
function M.analyze_menu()
	M.show_menu({
		{ "[B]acklinks", "b", M.backlinks },
		{ "[G]raph View", "g", M.show_graph },
	}, "Analyze", M.picker)
end

-- Tools submenu
function M.tools_menu()
	M.show_menu({
		{ "[E]dit Daily Template", "e", M.edit_daily_template },
		{ "[C]leanup Empty Dailies", "c", M.cleanup },
		{ "[I]nbox", "i", M.inbox },
	}, "Tools", M.picker)
end

-- Main picker entry point
function M.picker()
	M.show_menu(get_main_choices(), "womwiki")
end

--------------------------------------------------------------------------------
-- Backward compatibility: hello world test
--------------------------------------------------------------------------------

function M.hello()
	vim.notify("Hello from womwiki!", vim.log.levels.INFO)
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------

-- Setup highlights on load
utils.setup_graph_highlights()

return M

-- womwiki/tags.lua
-- Tags and frontmatter support: parse, index, browse, filter

local config = require("womwiki.config")
local patterns = config.patterns
local utils = require("womwiki.utils")

local M = {}

--- Strip inline code spans so tags inside backticks aren't matched
local function strip_inline_code(s)
	return s:gsub("`[^`]+`", "")
end

-- Tag index cache
M.cache = {
	index = {}, -- tag -> [{path, title, full_path}, ...]
	file_tags = {}, -- full_path -> [tag, ...]
	all_tags = {}, -- sorted list of all tags
	last_scan = 0,
	ttl = 300, -- seconds before stale (overridden by config.completion.cache_ttl)
	rebuilding = false, -- true while async rebuild is in progress
}

--------------------------------------------------------------------------------
-- Frontmatter Parsing
--------------------------------------------------------------------------------

--- Parse YAML frontmatter from a file
--- @param filepath string Absolute path to file
--- @return table|nil Parsed frontmatter {tags = {...}} or nil
function M.parse_frontmatter(filepath)
	local lines = utils.read_lines(filepath)
	if not lines then
		return nil
	end

	if #lines == 0 or lines[1] ~= "---" then
		return nil
	end

	local yaml_lines = {}
	for i = 2, #lines do
		if lines[i] == "---" then
			break
		end
		table.insert(yaml_lines, lines[i])
	end

	-- Parse tags from YAML
	local result = { tags = {} }
	local yaml = table.concat(yaml_lines, "\n")

	-- Match tags: [a, b, c] format (inline array)
	local tags_inline = yaml:match("tags:%s*%[([^%]]+)%]")
	if tags_inline then
		for tag in tags_inline:gmatch("([^,]+)") do
			local trimmed = vim.trim(tag):gsub("^['\"]", ""):gsub("['\"]$", "")
			if trimmed ~= "" then
				table.insert(result.tags, trimmed)
			end
		end
		return result
	end

	-- Match tags: followed by - items (multi-line list)
	local in_tags = false
	for _, line in ipairs(yaml_lines) do
		if line:match("^tags:%s*$") then
			in_tags = true
		elseif in_tags then
			local tag = line:match("^%s*%-%s*(.+)$")
			if tag then
				local trimmed = vim.trim(tag):gsub("^['\"]", ""):gsub("['\"]$", "")
				if trimmed ~= "" then
					table.insert(result.tags, trimmed)
				end
			else
				-- Non-list line ends the tags section
				in_tags = false
			end
		end
	end

	return result
end

--------------------------------------------------------------------------------
-- Inline Tag Extraction
--------------------------------------------------------------------------------

--- Extract inline #tags from file content
--- @param filepath string Absolute path to file
--- @return string[] List of tags found
function M.get_inline_tags(filepath)
	if not config.config.tags or not config.config.tags.enabled then
		return {}
	end

	local pattern = config.config.tags.inline_pattern or patterns.TAG_INLINE
	local tags = {}
	local seen = {}

	local lines = utils.read_lines(filepath)
	if not lines or #lines == 0 then
		return tags
	end

	local start_idx
	-- Skip frontmatter if present
	if lines[1] == "---" then
		start_idx = #lines + 1
		for i = 2, #lines do
			if lines[i] == "---" then
				start_idx = i + 1
				break
			end
		end
	else
		-- Process first line if not frontmatter
		for tag in strip_inline_code(lines[1]):gmatch(pattern) do
			if not seen[tag] then
				seen[tag] = true
				table.insert(tags, tag)
			end
		end
		start_idx = 2
	end

	-- Process rest of file
	for i = start_idx, #lines do
		local line = lines[i]
		-- Skip code blocks
		if not line:match("^```") then
			for tag in strip_inline_code(line):gmatch(pattern) do
				if not seen[tag] then
					seen[tag] = true
					table.insert(tags, tag)
				end
			end
		end
	end

	return tags
end

--------------------------------------------------------------------------------
-- Combined Tag Extraction
--------------------------------------------------------------------------------

--- Get all tags from a file (frontmatter + inline)
--- @param filepath string Absolute path to file
--- @return string[] List of unique tags
function M.get_file_tags(filepath)
	local tags = {}
	local seen = {}

	-- Get frontmatter tags
	if not config.config.tags or config.config.tags.use_frontmatter ~= false then
		local fm = M.parse_frontmatter(filepath)
		if fm and fm.tags then
			for _, tag in ipairs(fm.tags) do
				if not seen[tag] then
					seen[tag] = true
					table.insert(tags, tag)
				end
			end
		end
	end

	-- Get inline tags
	local inline = M.get_inline_tags(filepath)
	for _, tag in ipairs(inline) do
		if not seen[tag] then
			seen[tag] = true
			table.insert(tags, tag)
		end
	end

	return tags
end

--------------------------------------------------------------------------------
-- Single-pass File Metadata Reader
--------------------------------------------------------------------------------

--- Parse frontmatter YAML lines for tags
--- @param yaml_lines string[] Lines between --- delimiters
--- @return string[] List of tags from frontmatter
local function parse_frontmatter_tags(yaml_lines)
	local tags = {}
	local yaml = table.concat(yaml_lines, "\n")

	-- Match tags: [a, b, c] format (inline array)
	local tags_inline = yaml:match("tags:%s*%[([^%]]+)%]")
	if tags_inline then
		for tag in tags_inline:gmatch("([^,]+)") do
			local trimmed = vim.trim(tag):gsub("^['\"]", ""):gsub("['\"]$", "")
			if trimmed ~= "" then
				table.insert(tags, trimmed)
			end
		end
		return tags
	end

	-- Match tags: followed by - items (multi-line list)
	local in_tags = false
	for _, line in ipairs(yaml_lines) do
		if line:match("^tags:%s*$") then
			in_tags = true
		elseif in_tags then
			local tag = line:match("^%s*%-%s*(.+)$")
			if tag then
				local trimmed = vim.trim(tag):gsub("^['\"]", ""):gsub("['\"]$", "")
				if trimmed ~= "" then
					table.insert(tags, trimmed)
				end
			else
				in_tags = false
			end
		end
	end

	return tags
end

--- Read file once and extract title, frontmatter tags, and inline tags
--- @param filepath string Absolute path to file
--- @return table { title = string|nil, tags = string[] }
function M.read_file_metadata(filepath)
	local result = { title = nil, tags = {} }
	local seen = {}

	local lines = utils.read_lines(filepath)
	if not lines or #lines == 0 then
		return result
	end

	local inline_pattern = (config.config.tags and config.config.tags.inline_pattern) or patterns.TAG_INLINE
	local use_frontmatter = not config.config.tags or config.config.tags.use_frontmatter ~= false
	local tags_enabled = not config.config.tags or config.config.tags.enabled ~= false
	local in_code_block = false

	local start_idx
	-- Parse frontmatter if present
	if lines[1] == "---" and use_frontmatter then
		local yaml_lines = {}
		start_idx = #lines + 1
		for i = 2, #lines do
			if lines[i] == "---" then
				start_idx = i + 1
				break
			end
			table.insert(yaml_lines, lines[i])
		end
		local fm_tags = parse_frontmatter_tags(yaml_lines)
		for _, tag in ipairs(fm_tags) do
			if not seen[tag] then
				seen[tag] = true
				table.insert(result.tags, tag)
			end
		end
	else
		-- First line is content — check for title and inline tags
		local h1 = lines[1]:match(patterns.HEADING_H1)
		if h1 then
			result.title = h1
		end
		if tags_enabled then
			for tag in strip_inline_code(lines[1]):gmatch(inline_pattern) do
				if not seen[tag] then
					seen[tag] = true
					table.insert(result.tags, tag)
				end
			end
		end
		start_idx = 2
	end

	-- Process remaining lines
	for i = start_idx, #lines do
		local line = lines[i]
		-- Extract title from first H1 if we don't have one yet
		if not result.title then
			local h1 = line:match(patterns.HEADING_H1)
			if h1 then
				result.title = h1
			end
		end

		-- Track code blocks
		if line:match("^```") then
			in_code_block = not in_code_block
		end

		-- Extract inline tags (outside code blocks)
		if tags_enabled and not in_code_block then
			for tag in strip_inline_code(line):gmatch(inline_pattern) do
				if not seen[tag] then
					seen[tag] = true
					table.insert(result.tags, tag)
				end
			end
		end
	end

	return result
end

--------------------------------------------------------------------------------
-- Tag Index Building
--------------------------------------------------------------------------------

--- Build tag index from all wiki files
--- @return table Tag index {tag -> [{path, title, full_path}, ...]}
function M.build_tag_index()
	local files_mod = require("womwiki.files")
	local wiki_files = files_mod.get_wiki_files()

	M.cache.index = {}
	M.cache.file_tags = {}
	local all_tags_set = {}

	for _, file in ipairs(wiki_files) do
		local meta = M.read_file_metadata(file.full_path)
		-- Update file title if we got a better one from the full read
		if meta.title then
			file.title = meta.title
		end
		M.cache.file_tags[file.full_path] = meta.tags

		for _, tag in ipairs(meta.tags) do
			all_tags_set[tag] = true
			if not M.cache.index[tag] then
				M.cache.index[tag] = {}
			end
			table.insert(M.cache.index[tag], file)
		end
	end

	-- Build sorted list of all tags
	M.cache.all_tags = vim.tbl_keys(all_tags_set)
	table.sort(M.cache.all_tags)

	M.cache.last_scan = os.time()
	return M.cache.index
end

--- Async tag index rebuild using ripgrep (much faster for large wikis)
--- Falls back to Lua-based build_tag_index if rg is not available.
--- @param callback function|nil Called when rebuild is complete
function M.build_tag_index_rg(callback)
	local wikidir = config.wikidir
	if not wikidir then
		if callback then
			callback()
		end
		return
	end

	-- Convert Lua pattern to a regex approximation for rg
	-- The default pattern #([%w_-]+) becomes #[\w_-]+
	local rg_pattern = "#[\\w_-]+"

	local stdout_data = {}

	vim.fn.jobstart({ "rg", "--no-filename", "-oN", "--glob", "*.md", rg_pattern, wikidir }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			stdout_data = data
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code ~= 0 and exit_code ~= 1 then
					-- rg failed (not just "no matches"), fall back to Lua
					M.build_tag_index()
					if callback then
						callback()
					end
					return
				end

				-- Parse rg output: each line is a match like "#tagname"
				local all_tags_set = {}
				for _, line in ipairs(stdout_data) do
					if line ~= "" then
						local tag = line:match(patterns.TAG_START)
						if tag then
							all_tags_set[tag] = true
						end
					end
				end

				-- We only get the tag names from rg, not file associations.
				-- For the tag index (tag -> files mapping), we still need the
				-- full Lua scan. But for completion (which only needs tag names),
				-- we can update all_tags immediately and do the full rebuild later.
				M.cache.all_tags = vim.tbl_keys(all_tags_set)
				table.sort(M.cache.all_tags)
				M.cache.last_scan = os.time()

				-- Now do the full rebuild in the background for tag->file mapping
				vim.schedule(function()
					M.build_tag_index()
					if callback then
						callback()
					end
				end)
			end)
		end,
	})
end

--- Check if ripgrep is available
--- @return boolean
local rg_available = nil
local function has_rg()
	if rg_available == nil then
		rg_available = vim.fn.executable("rg") == 1
	end
	return rg_available
end

--- Get tag index (returns stale data immediately, rebuilds async if needed)
--- @return table Tag index
function M.get_tag_index()
	local ttl = (config.config.completion and config.config.completion.cache_ttl) or M.cache.ttl
	local now = os.time()
	if now - M.cache.last_scan > ttl and not M.cache.rebuilding then
		-- If we have no data at all, do a synchronous build (first load)
		if M.cache.last_scan == 0 then
			M.build_tag_index()
		else
			-- Return stale data now, rebuild in background
			M.cache.rebuilding = true
			if has_rg() then
				M.build_tag_index_rg(function()
					M.cache.rebuilding = false
				end)
			else
				vim.schedule(function()
					M.build_tag_index()
					M.cache.rebuilding = false
				end)
			end
		end
	end
	return M.cache.index
end

--- Get all tags (builds index if stale)
--- @return string[] Sorted list of all tags
function M.get_all_tags()
	M.get_tag_index() -- Ensure cache is fresh (or trigger async refresh)
	return M.cache.all_tags
end

--- Invalidate cache (call after file changes)
function M.invalidate_cache()
	M.cache.last_scan = 0
end

--------------------------------------------------------------------------------
-- Tag Commands
--------------------------------------------------------------------------------

--- List all tags with counts (picker)
function M.list_tags()
	if not config.is_valid() then
		vim.notify("womwiki: Wiki directory not configured or not found", vim.log.levels.ERROR)
		return
	end

	local index = M.get_tag_index()
	local all_tags = M.get_all_tags()

	if #all_tags == 0 then
		vim.notify("No tags found in wiki", vim.log.levels.INFO)
		return
	end

	local _, has_picker = utils.get_picker()
	if not has_picker then
		-- Fallback: show in floating window
		M.list_tags_float(all_tags, index)
		return
	end

	-- Build display items: "tag (count)"
	local items = {}
	for _, tag in ipairs(all_tags) do
		local count = #(index[tag] or {})
		table.insert(items, {
			display = string.format("#%s (%d)", tag, count),
			tag = tag,
			count = count,
		})
	end

	local display_items = vim.tbl_map(function(item)
		return item.display
	end, items)
	utils.picker_select(display_items, { title = "Tags" }, function(selected)
		local tag = selected:match(patterns.TAG_START)
		if not tag then
			vim.notify("Failed to parse tag from selection", vim.log.levels.WARN)
			return
		end
		M.filter_by_tag(tag)
	end)
end

--- Fallback: show tags in floating window
function M.list_tags_float(all_tags, index)
	local lines = { "Tags", "" }
	for _, tag in ipairs(all_tags) do
		local count = #(index[tag] or {})
		table.insert(lines, string.format("  #%s (%d)", tag, count))
	end
	table.insert(lines, "")
	table.insert(lines, "Press q to close")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"

	local width = 40
	local height = math.min(#lines, 20)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.ceil((vim.o.columns - width) / 2),
		row = math.ceil((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
	})

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, nowait = true })
end

--- Filter files by tag (picker showing files with that tag)
--- @param tag string|nil Tag to filter by (prompts if nil)
function M.filter_by_tag(tag)
	if not config.is_valid() then
		vim.notify("womwiki: Wiki directory not configured or not found", vim.log.levels.ERROR)
		return
	end

	if not tag then
		-- Prompt for tag
		local all_tags = M.get_all_tags()
		if #all_tags == 0 then
			vim.notify("No tags found in wiki", vim.log.levels.INFO)
			return
		end
		vim.ui.select(all_tags, { prompt = "Select tag:" }, function(selected)
			if selected then
				M.filter_by_tag(selected)
			end
		end)
		return
	end

	local index = M.get_tag_index()
	local files = index[tag]

	if not files or #files == 0 then
		vim.notify("No files with tag: #" .. tag, vim.log.levels.INFO)
		return
	end

	local display_items = vim.tbl_map(function(file)
		return file.path .. " - " .. file.title
	end, files)
	utils.picker_select(display_items, { title = "Files tagged #" .. tag }, function(selected)
		local path = selected:match("^([^%s]+)")
		if not path then
			vim.notify("Failed to parse selection", vim.log.levels.WARN)
			return
		end
		for _, file in ipairs(files) do
			if file.path == path then
				utils.open_wiki_file(file.full_path)
				break
			end
		end
	end)
end

--- Add tag to current file
--- @param tag string|nil Tag to add (prompts if nil)
function M.add_tag(tag)
	local filepath = vim.fn.expand("%:p")
	if not filepath:match("%.md$") then
		vim.notify("Not a markdown file", vim.log.levels.WARN)
		return
	end

	if not tag then
		vim.ui.input({ prompt = "Tag to add: " }, function(input)
			if input and input ~= "" then
				-- Remove # prefix if user typed it
				input = input:gsub("^#", "")
				M.add_tag(input)
			end
		end)
		return
	end

	-- Check if file has frontmatter
	local lines = utils.read_lines(filepath)
	if not lines then
		vim.notify("Cannot read file", vim.log.levels.ERROR)
		return
	end

	local has_frontmatter = #lines > 0 and lines[1] == "---"

	if has_frontmatter and (not config.config.tags or config.config.tags.use_frontmatter ~= false) then
		-- Add to frontmatter
		local fm_end = nil
		for i = 2, #lines do
			if lines[i] == "---" then
				fm_end = i
				break
			end
		end

		if fm_end then
			-- Check if tags line exists
			local tags_line = nil
			for i = 2, fm_end - 1 do
				if lines[i]:match("^tags:") then
					tags_line = i
					break
				end
			end

			if tags_line then
				-- Add to existing tags line
				local current = lines[tags_line]
				if current:match("%[.*%]") then
					-- Inline array format: tags: [a, b]
					local new_line = current:gsub("%]$", ", " .. tag .. "]")
					-- Handle empty array
					new_line = new_line:gsub("%[, ", "[")
					lines[tags_line] = new_line
				else
					-- Multi-line format, add after
					table.insert(lines, tags_line + 1, "  - " .. tag)
				end
			else
				-- Add new tags line before frontmatter end
				table.insert(lines, fm_end, "tags: [" .. tag .. "]")
			end
		end
	else
		-- Add inline tag at end of first heading or first line
		local insert_line = 1
		for i, line in ipairs(lines) do
			if line:match("^#%s+") then
				insert_line = i
				break
			end
		end
		-- Append tag to end of that line
		lines[insert_line] = lines[insert_line] .. " #" .. tag
	end

	-- Write back
	if not utils.write_file(filepath, table.concat(lines, "\n")) then
		vim.notify("Cannot write file", vim.log.levels.ERROR)
		return
	end

	-- Reload buffer
	vim.cmd("edit!")
	vim.notify("Added tag: #" .. tag, vim.log.levels.INFO)

	-- Invalidate cache
	M.invalidate_cache()
end

return M

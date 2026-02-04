-- womwiki/tags.lua
-- Tags and frontmatter support: parse, index, browse, filter

local config = require("womwiki.config")
local utils = require("womwiki.utils")

local M = {}

-- Tag index cache
M.cache = {
	index = {}, -- tag -> [{path, title, full_path}, ...]
	file_tags = {}, -- full_path -> [tag, ...]
	all_tags = {}, -- sorted list of all tags
	last_scan = 0,
	ttl = 60, -- seconds before stale
}

--------------------------------------------------------------------------------
-- Frontmatter Parsing
--------------------------------------------------------------------------------

--- Parse YAML frontmatter from a file
--- @param filepath string Absolute path to file
--- @return table|nil Parsed frontmatter {tags = {...}} or nil
function M.parse_frontmatter(filepath)
	local f = io.open(filepath, "r")
	if not f then
		return nil
	end

	local first_line = f:read("*l")
	if not first_line or first_line ~= "---" then
		f:close()
		return nil
	end

	local yaml_lines = {}
	for line in f:lines() do
		if line == "---" then
			break
		end
		table.insert(yaml_lines, line)
	end
	f:close()

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

	local pattern = config.config.tags.inline_pattern or "#([%w_-]+)"
	local tags = {}
	local seen = {}

	local f = io.open(filepath, "r")
	if not f then
		return tags
	end

	-- Skip frontmatter if present
	local first_line = f:read("*l")
	local in_frontmatter = first_line == "---"
	if in_frontmatter then
		for line in f:lines() do
			if line == "---" then
				break
			end
		end
	elseif first_line then
		-- Process first line if not frontmatter
		for tag in first_line:gmatch(pattern) do
			if not seen[tag] then
				seen[tag] = true
				table.insert(tags, tag)
			end
		end
	end

	-- Process rest of file
	for line in f:lines() do
		-- Skip code blocks
		if not line:match("^```") then
			for tag in line:gmatch(pattern) do
				if not seen[tag] then
					seen[tag] = true
					table.insert(tags, tag)
				end
			end
		end
	end

	f:close()
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
		local tags = M.get_file_tags(file.full_path)
		M.cache.file_tags[file.full_path] = tags

		for _, tag in ipairs(tags) do
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

--- Get tag index (builds if stale)
--- @return table Tag index
function M.get_tag_index()
	local now = os.time()
	if now - M.cache.last_scan > M.cache.ttl then
		M.build_tag_index()
	end
	return M.cache.index
end

--- Get all tags (builds index if stale)
--- @return string[] Sorted list of all tags
function M.get_all_tags()
	M.get_tag_index() -- Ensure cache is fresh
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
	local index = M.get_tag_index()
	local all_tags = M.get_all_tags()

	if #all_tags == 0 then
		vim.notify("No tags found in wiki", vim.log.levels.INFO)
		return
	end

	local picker_type, picker = utils.get_picker()
	if not picker then
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

	if picker_type == "telescope" then
		require("telescope.pickers")
			.new({}, {
				prompt_title = "Tags",
				finder = require("telescope.finders").new_table({
					results = items,
					entry_maker = function(item)
						return {
							value = item,
							display = item.display,
							ordinal = item.tag,
						}
					end,
				}),
				sorter = require("telescope.config").values.generic_sorter({}),
				attach_mappings = function(_, map)
					map("i", "<CR>", function(prompt_bufnr)
						local selection = require("telescope.actions.state").get_selected_entry()
						require("telescope.actions").close(prompt_bufnr)
						if selection then
							M.filter_by_tag(selection.value.tag)
						end
					end)
					return true
				end,
			})
			:find()
	elseif picker_type == "fzf" then
		local display_items = vim.tbl_map(function(item)
			return item.display
		end, items)
		picker.fzf_exec(display_items, {
			prompt = "Tags> ",
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						local tag = selected[1]:match("^#([%w_-]+)")
						if tag then
							M.filter_by_tag(tag)
						end
					end
				end,
			},
		})
	elseif picker_type == "mini" then
		local display_items = vim.tbl_map(function(item)
			return item.display
		end, items)
		picker.start({
			source = { items = display_items, name = "Tags" },
			choose = function(item)
				local tag = item:match("^#([%w_-]+)")
				if tag then
					M.filter_by_tag(tag)
				end
			end,
		})
	elseif picker_type == "snacks" then
		local display_items = vim.tbl_map(function(item)
			return item.display
		end, items)
		picker.picker.pick({
			source = display_items,
			prompt = "Tags",
			confirm = function(item)
				local tag = item:match("^#([%w_-]+)")
				if tag then
					M.filter_by_tag(tag)
				end
			end,
		})
	end
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

	local picker_type, picker = utils.get_picker()
	if not picker then
		-- Fallback: open first file
		utils.open_wiki_file(files[1].full_path)
		return
	end

	if picker_type == "telescope" then
		require("telescope.pickers")
			.new({}, {
				prompt_title = "Files tagged #" .. tag,
				finder = require("telescope.finders").new_table({
					results = files,
					entry_maker = function(file)
						return {
							value = file,
							display = file.path .. " - " .. file.title,
							ordinal = file.path .. " " .. file.title,
						}
					end,
				}),
				sorter = require("telescope.config").values.generic_sorter({}),
				attach_mappings = function(_, map)
					map("i", "<CR>", function(prompt_bufnr)
						local selection = require("telescope.actions.state").get_selected_entry()
						require("telescope.actions").close(prompt_bufnr)
						if selection then
							utils.open_wiki_file(selection.value.full_path)
						end
					end)
					return true
				end,
			})
			:find()
	elseif picker_type == "fzf" then
		local display_items = vim.tbl_map(function(file)
			return file.path .. " - " .. file.title
		end, files)
		picker.fzf_exec(display_items, {
			prompt = "Files tagged #" .. tag .. "> ",
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						local path = selected[1]:match("^([^%s]+)")
						for _, file in ipairs(files) do
							if file.path == path then
								utils.open_wiki_file(file.full_path)
								break
							end
						end
					end
				end,
			},
		})
	elseif picker_type == "mini" then
		local display_items = vim.tbl_map(function(file)
			return file.path .. " - " .. file.title
		end, files)
		picker.start({
			source = { items = display_items, name = "Files tagged #" .. tag },
			choose = function(item)
				local path = item:match("^([^%s]+)")
				for _, file in ipairs(files) do
					if file.path == path then
						utils.open_wiki_file(file.full_path)
						break
					end
				end
			end,
		})
	elseif picker_type == "snacks" then
		local display_items = vim.tbl_map(function(file)
			return file.path .. " - " .. file.title
		end, files)
		picker.picker.pick({
			source = display_items,
			prompt = "Files tagged #" .. tag,
			confirm = function(item)
				local path = item:match("^([^%s]+)")
				for _, file in ipairs(files) do
					if file.path == path then
						utils.open_wiki_file(file.full_path)
						break
					end
				end
			end,
		})
	end
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
	local f = io.open(filepath, "r")
	if not f then
		vim.notify("Cannot read file", vim.log.levels.ERROR)
		return
	end

	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()

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
	f = io.open(filepath, "w")
	if not f then
		vim.notify("Cannot write file", vim.log.levels.ERROR)
		return
	end
	f:write(table.concat(lines, "\n"))
	f:close()

	-- Reload buffer
	vim.cmd("edit!")
	vim.notify("Added tag: #" .. tag, vim.log.levels.INFO)

	-- Invalidate cache
	M.invalidate_cache()
end

return M

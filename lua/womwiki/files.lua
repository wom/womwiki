-- womwiki/files.lua
-- File navigation: wiki, dailies, recent, search, create

local config = require("womwiki.config")
local patterns = config.patterns
local utils = require("womwiki.utils")

local M = {}

-- File list cache
M.cache = {
	files = {},
	last_scan = 0,
	ttl = 300, -- seconds, overridden by config.completion.cache_ttl
}

--- Invalidate the wiki files cache (call after file changes)
function M.invalidate_cache()
	M.cache.last_scan = 0
end

--- Open picker to find files in the wiki directory
function M.wiki()
	if not config.is_valid() then
		vim.notify("womwiki: Wiki directory not configured or not found", vim.log.levels.ERROR)
		return
	end

	local picker_type, picker = utils.get_picker()
	if not picker then
		return
	end

	if picker_type == "telescope" then
		picker.find_files({ cwd = config.wikidir, hidden = false })
	elseif picker_type == "mini" then
		picker.builtin.files({}, { source = { cwd = config.wikidir } })
	elseif picker_type == "snacks" then
		picker.picker.files({ cwd = config.wikidir })
	elseif picker_type == "fzf" then
		picker.files({ cwd = config.wikidir })
	end
end

--- Open picker to find files in the daily directory
function M.dailies()
	if not config.is_valid() then
		vim.notify("womwiki: Wiki directory not configured or not found", vim.log.levels.ERROR)
		return
	end

	local picker_type, picker = utils.get_picker()
	if not picker then
		return
	end

	if picker_type == "telescope" then
		picker.find_files({ cwd = config.dailydir, hidden = false })
	elseif picker_type == "mini" then
		picker.builtin.files({}, { source = { cwd = config.dailydir } })
	elseif picker_type == "snacks" then
		picker.picker.files({ cwd = config.dailydir })
	elseif picker_type == "fzf" then
		picker.files({ cwd = config.dailydir })
	end
end

--- Get list of subdirectories in wiki directory
--- @return string[] Absolute paths including the root wiki directory
function M.get_wiki_folders()
	if not config.is_valid() then
		return {}
	end

	local folders = { config.wikidir } -- Always include root wiki directory
	local handle = vim.uv.fs_scandir(config.wikidir)
	if handle then
		while true do
			local name, type = vim.uv.fs_scandir_next(handle)
			if not name then
				break
			end
			if type == "directory" then
				table.insert(folders, config.wikidir .. "/" .. name)
			end
		end
	end
	return folders
end

--- Create a new wiki file via interactive folder/name selection
function M.create()
	local folders = M.get_wiki_folders()
	local folder_names = {}
	for _, folder in ipairs(folders) do
		if folder == config.wikidir then
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
					filename = utils.ensure_md_extension(filename)
					local full_path = selected_folder .. "/" .. filename

					-- Check if file already exists
					local file = io.open(full_path, "r")
					if file then
						file:close()
						-- File exists, just open it
						utils.open_wiki_file(full_path)
					else
						-- Create new file
						local ok = utils.write_file(full_path, "# " .. filename:gsub("%.md$", "") .. "\n\n")
						if ok then
							utils.open_wiki_file(full_path)
						else
							vim.notify("Failed to create file: " .. full_path, vim.log.levels.ERROR)
						end
					end
				end
			end)
		end
	end)
end

--- Open recent wiki files using the available picker
function M.recent()
	if not config.is_valid() then
		vim.notify("womwiki: Wiki directory not configured or not found", vim.log.levels.ERROR)
		return
	end

	-- Get all oldfiles and filter them manually
	local oldfiles = vim.v.oldfiles or {}
	local wiki_files = {}

	for _, file in ipairs(oldfiles) do
		-- Expand tilde in file path for comparison
		local expanded_file = vim.fn.expand(file)
		-- Check if file starts with wiki directory path (plain string match)
		if vim.startswith(expanded_file, config.wikidir) then
			table.insert(wiki_files, file)
		end
	end

	if #wiki_files == 0 then
		vim.notify("No recent wiki files found", vim.log.levels.INFO)
		return
	end

	utils.picker_select(wiki_files, { title = "Recent Wiki Files" }, function(selected)
		utils.open_wiki_file(selected)
	end)
end

--- Search through wiki files using the available picker
function M.search()
	if not config.is_valid() then
		vim.notify("womwiki: Wiki directory not configured or not found", vim.log.levels.ERROR)
		return
	end

	utils.picker_grep({ cwd = config.wikidir })
end

--- Get all wiki files with their titles (used by completion)
--- Results are cached with a TTL to avoid rescanning on every keystroke
--- @return table[] Array of {path: string, title: string, full_path: string}
function M.get_wiki_files()
	if not config.is_valid() then
		return {}
	end

	local ttl = (config.config.completion and config.config.completion.cache_ttl) or M.cache.ttl
	local now = os.time()
	if now - M.cache.last_scan < ttl and #M.cache.files > 0 then
		return M.cache.files
	end

	local files = {}

	local function scan_dir(dir, prefix)
		local h = vim.uv.fs_scandir(dir)
		if not h then
			return
		end

		while true do
			local name, type = vim.uv.fs_scandir_next(h)
			if not name then
				break
			end

			local full_path = dir .. "/" .. name
			local rel_path = prefix ~= "" and (prefix .. "/" .. name) or name

			if type == "directory" and not name:match("^%.") then
				scan_dir(full_path, rel_path)
			elseif type == "file" and name:match("%.md$") then
				local title = nil
				local file_lines = utils.read_lines(full_path)
				if file_lines then
					for _, line in ipairs(file_lines) do
						local h1 = line:match(patterns.HEADING_H1)
						if h1 then
							title = h1
							break
						end
					end
				end

				table.insert(files, {
					path = rel_path,
					title = title or rel_path:gsub("%.md$", ""),
					full_path = full_path,
				})
			end
		end
	end

	scan_dir(config.wikidir, "")
	M.cache.files = files
	M.cache.last_scan = now
	return files
end

--- Get headings from a markdown file
--- @param filepath string Absolute path to the markdown file
--- @return table[] Array of {text: string, slug: string, level: integer}
function M.get_file_headings(filepath)
	local headings = {}
	local lines = utils.read_lines(filepath)
	if not lines then
		return headings
	end

	for _, line in ipairs(lines) do
		local level, text = line:match("^(#+)%s+(.+)$")
		if level and text then
			local slug =
				text:lower():gsub("[^%w%s-]", ""):gsub("%s+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
			table.insert(headings, {
				text = text,
				slug = slug,
				level = #level,
			})
		end
	end

	return headings
end

--- Replace link references from old_key to new_key in a file's content
--- @param content string File content
--- @param old_key string Old link target (relative path without .md)
--- @param new_key string New link target (relative path without .md)
--- @return string Updated content
--- @return integer Number of replacements made
local function replace_link_references(content, old_key, new_key)
	local count = 0

	-- Replace wikilinks: [[old_key]] → [[new_key]]
	local new_content, n1 = content:gsub("%[%[" .. vim.pesc(old_key) .. "%]%]", "[[" .. new_key .. "]]")
	count = count + n1

	-- Replace wikilinks with display: [[old_key|display]] → [[new_key|display]]
	new_content, n1 = new_content:gsub("%[%[" .. vim.pesc(old_key) .. "|", "[[" .. new_key .. "|")
	count = count + n1

	-- Replace markdown links with .md: [text](old_key.md) → [text](new_key.md)
	new_content, n1 = new_content:gsub("(%]%()(" .. vim.pesc(old_key) .. "%.md)(%))", "%1" .. new_key .. ".md%3")
	count = count + n1

	-- Replace markdown links without .md: [text](old_key) → [text](new_key)
	-- Must not match .md version (already handled above)
	new_content, n1 = new_content:gsub("(%]%()(" .. vim.pesc(old_key) .. ")(%))", "%1" .. new_key .. "%3")
	count = count + n1

	return new_content, count
end

--- Expose for testing
M._replace_link_references = replace_link_references

--- Rename a wiki file and update all inbound links across the wiki
function M.rename()
	if not config.is_valid() then
		vim.notify("womwiki: Wiki directory not configured or not found", vim.log.levels.ERROR)
		return
	end

	local current_path = vim.fn.expand("%:p")
	if not vim.startswith(current_path, config.wikidir .. "/") then
		vim.notify("Not in a wiki file", vim.log.levels.WARN)
		return
	end

	local old_relative = current_path:sub(#config.wikidir + 2)
	local old_key = old_relative:gsub("%.md$", "")
	local old_basename = vim.fn.fnamemodify(old_relative, ":t:r")
	local parent_dir = vim.fn.fnamemodify(old_relative, ":h")

	vim.ui.input({ prompt = "Rename to: ", default = old_basename }, function(new_name)
		if not new_name or new_name == "" or new_name == old_basename then
			return
		end

		-- Compute new key and path
		local new_key = parent_dir == "." and new_name or (parent_dir .. "/" .. new_name)
		local new_relative = new_key .. ".md"
		local new_path = config.wikidir .. "/" .. new_relative

		-- Check if target already exists
		if vim.uv.fs_stat(new_path) then
			vim.notify("File already exists: " .. new_relative, vim.log.levels.ERROR)
			return
		end

		-- Get graph to find all files that link to this one
		local graph = require("womwiki.graph")
		local link_graph = graph.get_link_graph()
		local node = link_graph[old_key]

		local updated_files = 0

		if node and #node.linked_from > 0 then
			for _, source_key in ipairs(node.linked_from) do
				local source_node = link_graph[source_key]
				if source_node then
					local content = utils.read_file(source_node.path)
					if content then
						local new_content, replacements = replace_link_references(content, old_key, new_key)
						if replacements > 0 then
							utils.write_file(source_node.path, new_content)
							updated_files = updated_files + 1
						end
					end
				end
			end
		end

		-- Rename the actual file
		local ok, err = os.rename(current_path, new_path)
		if not ok then
			vim.notify("Failed to rename file: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return
		end

		-- Update current buffer to point to new file
		vim.cmd("edit " .. vim.fn.fnameescape(new_path))

		-- Invalidate all caches
		M.invalidate_cache()
		require("womwiki.tags").invalidate_cache()
		graph.invalidate_cache()

		local msg = "Renamed to " .. new_relative
		if updated_files > 0 then
			msg = msg .. " (updated links in " .. updated_files .. " file" .. (updated_files > 1 and "s" or "") .. ")"
		end
		vim.notify(msg, vim.log.levels.INFO)
	end)
end

return M

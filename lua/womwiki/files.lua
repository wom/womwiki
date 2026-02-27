-- womwiki/files.lua
-- File navigation: wiki, dailies, recent, search, create

local config = require("womwiki.config")
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

-- Open picker to find files in the wiki directory
function M.wiki()
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

-- Open picker to find files in the daily directory
function M.dailies()
	local picker_type, picker = utils.get_picker()
	if not picker then
		return
	end

	-- Ensure dailydir is set
	if not config.dailydir or config.dailydir == "" then
		vim.notify("Daily directory not configured", vim.log.levels.ERROR)
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

-- Get list of subdirectories in wiki directory
function M.get_wiki_folders()
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

-- Create a new wiki file
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
						local new_file = io.open(full_path, "w")
						if new_file then
							new_file:write("# " .. filename:gsub("%.md$", "") .. "\n\n")
							new_file:close()
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

-- Open recent wiki files using available picker
function M.recent()
	local picker_type, picker = utils.get_picker()
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
		if vim.startswith(expanded_file, config.wikidir) then
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
							utils.open_wiki_file(selection.value)
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
				utils.open_wiki_file(item)
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
				utils.open_wiki_file(item)
			end,
		})
	elseif picker_type == "fzf" then
		picker.fzf_exec(wiki_files, {
			prompt = "Recent Wiki Files> ",
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						utils.open_wiki_file(selected[1])
					end
				end,
			},
			fzf_opts = { ["--sort"] = true },
		})
	end
end

-- Search through wiki files using available picker
function M.search()
	local picker_type, picker = utils.get_picker()
	if not picker then
		return
	end

	if picker_type == "telescope" then
		picker.live_grep({ cwd = config.wikidir })
	elseif picker_type == "mini" then
		-- Note: mini.pick doesn't have live_grep built-in, using grep builtin instead
		picker.builtin.grep_live({}, { source = { cwd = config.wikidir } })
	elseif picker_type == "snacks" then
		picker.picker.grep({ cwd = config.wikidir })
	elseif picker_type == "fzf" then
		picker.live_grep({ cwd = config.wikidir })
	end
end

-- Get all wiki files with their titles (used by completion)
-- Results are cached with a TTL to avoid rescanning on every keystroke
function M.get_wiki_files()
	if not config.wikidir then
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
				local f = io.open(full_path, "r")
				if f then
					for line in f:lines() do
						local h1 = line:match("^#%s+(.+)$")
						if h1 then
							title = h1
							break
						end
					end
					f:close()
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

-- Get headings from a file
function M.get_file_headings(filepath)
	local headings = {}
	local f = io.open(filepath, "r")
	if not f then
		return headings
	end

	for line in f:lines() do
		local level, text = line:match("^(#+)%s+(.+)$")
		if level and text then
			local slug = text:lower()
				:gsub("[^%w%s-]", "")
				:gsub("%s+", "-")
				:gsub("%-+", "-")
				:gsub("^%-", "")
				:gsub("%-$", "")
			table.insert(headings, {
				text = text,
				slug = slug,
				level = #level,
			})
		end
	end

	f:close()
	return headings
end

return M

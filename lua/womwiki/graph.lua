-- womwiki/graph.lua
-- Link graph visualization and backlinks analysis

local config = require("womwiki.config")
local utils = require("womwiki.utils")

local M = {}

-- Get all markdown links from a file
local function get_links_from_file(file_path)
	local links = {}
	local file = io.open(file_path, "r")
	if not file then
		return links
	end

	for line in file:lines() do
		-- Match [text](link) pattern (standard markdown)
		for _, link in line:gmatch("%[([^%]]+)%]%(([^%)]+)%)") do
			-- Skip URLs, only process local links
			if not link:match("^https?://") then
				-- Remove .md extension if present for consistency
				local clean_link = link:gsub("%.md$", "")
				table.insert(links, clean_link)
			end
		end

		-- Match [[link]] or [[link|display]] pattern (wikilinks)
		if config.config.wikilinks and config.config.wikilinks.enabled then
			for link_content in line:gmatch("%[%[([^%]]+)%]%]") do
				-- Parse [[link|display]] format - extract just the link part
				local link_target = link_content:match("^([^|]+)") or link_content
				-- Convert spaces based on config
				local spaces_to = config.config.wikilinks.spaces_to
				if spaces_to then
					link_target = link_target:gsub(" ", spaces_to)
				end
				table.insert(links, link_target)
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

	scan_directory(config.wikidir)
	return files
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

-- Show backlinks to current file
function M.backlinks()
	local current_file = vim.fn.expand("%:t:r")
	if current_file == "" then
		vim.notify("Not in a wiki file", vim.log.levels.WARN)
		return
	end

	local picker_type, picker = utils.get_picker()
	if not picker then
		return
	end

	-- Search for files that link to current file
	local search_patterns = {
		"\\]\\(" .. current_file .. "\\)", -- [text](filename)
		"\\]\\(" .. current_file .. "\\.md\\)", -- [text](filename.md)
	}

	-- Add wikilink patterns if enabled
	if config.config.wikilinks and config.config.wikilinks.enabled then
		table.insert(search_patterns, "\\[\\[" .. current_file .. "\\]\\]") -- [[filename]]
		table.insert(search_patterns, "\\[\\[" .. current_file .. "\\|[^\\]]*\\]\\]") -- [[filename|display]]
	end

	if picker_type == "telescope" then
		picker.grep_string({
			search = table.concat(search_patterns, "|"),
			cwd = config.wikidir,
			use_regex = true,
			prompt_title = "󰌷 Backlinks to: " .. current_file .. ".md",
		})
	elseif picker_type == "mini" then
		-- For mini.pick, we'll use a simpler approach
		picker.builtin.grep_live({
			default_text = current_file,
		}, { source = { cwd = config.wikidir } })
	elseif picker_type == "snacks" then
		picker.picker.grep({
			search = table.concat(search_patterns, "|"),
			cwd = config.wikidir,
		})
	elseif picker_type == "fzf" then
		picker.grep({
			search = table.concat(search_patterns, "|"),
			cwd = config.wikidir,
			no_esc = true, -- Don't escape regex pattern (allows | alternation)
			file_icons = false, -- Disable icons to simplify path parsing
			fzf_opts = {
				["--header"] = "󰌷 Backlinks to: " .. current_file .. ".md",
				["--preview"] = "bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || cat {1}",
				["--preview-window"] = "right:60%",
			},
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						-- Extract filename from "filename:line:content" format
						local file = selected[1]:match("^%s*([^:]+)")
						if file then
							file = vim.trim(file)
							utils.open_wiki_file(config.wikidir .. "/" .. file)
						end
					end
				end,
			},
		})
	end
end

-- Create ASCII art graph visualization
function M.show()
	local graph = build_link_graph()
	local current_file = vim.fn.expand("%:t:r")

	-- Build graph display
	local lines = {}
	local highlights = {} -- Track which lines need highlighting
	-- Make width responsive: 70% of screen width, min 60, max 120
	local max_width = math.max(60, math.min(120, math.floor(vim.o.columns * 0.7)))

	-- Header
	table.insert(lines, "╭─ Wiki Link Graph " .. string.rep("─", max_width - 18) .. "╮")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphBorder" })
	if current_file ~= "" then
		table.insert(lines, "│ Current: " .. current_file .. string.rep(" ", max_width - 10 - #current_file) .. "│")
		table.insert(
			highlights,
			{ line = #lines - 1, hl_group = "WomwikiGraphCurrent", col_start = 10, col_end = 10 + #current_file }
		)
	end
	table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphBorder" })

	-- Calculate stats
	local total_files = 0
	local total_links = 0
	local orphans = {}
	local hubs = {}

	-- Helper to check if file is in daily directory
	local function is_daily_note(filepath)
		local daily_prefix = config.dailydir:gsub("^" .. config.wikidir .. "/", "")
		return filepath:match("^" .. vim.pesc(daily_prefix) .. "/")
	end

	for name, data in pairs(graph) do
		total_files = total_files + 1
		total_links = total_links + #data.links_to

		-- Find true orphans (no connections at all, excluding daily notes)
		local total_connections = #data.linked_from + #data.links_to
		if total_connections == 0 and not is_daily_note(data.path) then
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

	-- Calculate connection density
	local avg_links = total_files > 0 and string.format("%.1f", total_links / total_files) or "0"

	-- Stats section with density
	local stats_line = "│ Files: "
		.. total_files
		.. " | Links: "
		.. total_links
		.. " | Avg: "
		.. avg_links
		.. " | Orphans: "
		.. #orphans
	local stats_padding = max_width - #stats_line + 1
	table.insert(lines, stats_line .. string.rep(" ", stats_padding) .. "│")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphStats" })
	table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphBorder" })

	-- Current file details (if in a wiki file)
	if current_file ~= "" and graph[current_file] then
		local data = graph[current_file]
		local total_conn = #data.links_to + #data.linked_from
		table.insert(
			lines,
			"│ Current file: "
				.. current_file
				.. " ("
				.. total_conn
				.. " connections)"
				.. string.rep(" ", max_width - 27 - #current_file - #tostring(total_conn))
				.. "│"
		)
		table.insert(
			highlights,
			{ line = #lines - 1, hl_group = "WomwikiGraphCurrent", col_start = 15, col_end = 15 + #current_file }
		)

		-- Links to (outgoing)
		if #data.links_to > 0 then
			local max_links_shown = 5
			local links_text = table.concat(vim.list_slice(data.links_to, 1, max_links_shown), ", ")
			if #data.links_to > max_links_shown then
				links_text = links_text .. " ... and " .. (#data.links_to - max_links_shown) .. " more"
			end
			local links_line = "│   → Links to (" .. #data.links_to .. "): " .. links_text
			table.insert(lines, links_line .. string.rep(" ", max_width - #links_line + 1) .. "│")
		else
			table.insert(lines, "│   → Links to (0): (none)" .. string.rep(" ", max_width - 23) .. "│")
		end

		-- Linked from (incoming/backlinks)
		if #data.linked_from > 0 then
			local max_links_shown = 5
			local backlinks_text = table.concat(vim.list_slice(data.linked_from, 1, max_links_shown), ", ")
			if #data.linked_from > max_links_shown then
				backlinks_text = backlinks_text .. " ... and " .. (#data.linked_from - max_links_shown) .. " more"
			end
			local backlinks_line = "│   ← Linked from (" .. #data.linked_from .. "): " .. backlinks_text
			table.insert(lines, backlinks_line .. string.rep(" ", max_width - #backlinks_line + 1) .. "│")
		else
			table.insert(lines, "│   ← Linked from (0): (none)" .. string.rep(" ", max_width - 26) .. "│")
		end

		table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
		table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphBorder" })
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

	-- Orphan files (limited display)
	if #orphans > 0 then
		local max_orphans_shown = 10
		table.insert(
			lines,
			"│ Orphan files (no connections, excluding dailies):" .. string.rep(" ", max_width - 50) .. "│"
		)

		-- Sort orphans alphabetically
		table.sort(orphans)

		-- Show first N orphans
		local orphans_to_show = {}
		for i = 1, math.min(max_orphans_shown, #orphans) do
			table.insert(orphans_to_show, orphans[i])
		end

		local orphan_text = table.concat(orphans_to_show, ", ")
		if #orphans > max_orphans_shown then
			orphan_text = orphan_text .. " ... and " .. (#orphans - max_orphans_shown) .. " more"
		end

		-- Word wrap orphan list
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

	-- Instructions with help text
	table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphBorder" })
	table.insert(lines, "│ Terminology:" .. string.rep(" ", max_width - 13) .. "│")
	table.insert(
		lines,
		"│   Hubs: Files with 3+ backlinks (well-connected)" .. string.rep(" ", max_width - 49) .. "│"
	)
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphHub", col_start = 4, col_end = 8 })
	table.insert(lines, "│   Orphans: Files with no connections at all" .. string.rep(" ", max_width - 44) .. "│")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphOrphan", col_start = 4, col_end = 11 })
	table.insert(lines, "├" .. string.rep("─", max_width) .. "┤")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphBorder" })
	local key_line1 = "│ [b]acklinks  [o]rphans  [h]ubs  [e]xpand  [/]search  [f]ind  [q]uit"
	table.insert(lines, key_line1 .. string.rep(" ", max_width - #key_line1 + 1) .. "│")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphKey" })
	table.insert(lines, "╰" .. string.rep("─", max_width) .. "╯")
	table.insert(highlights, { line = #lines - 1, hl_group = "WomwikiGraphBorder" })

	-- Display in floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Apply syntax highlighting
	local ns_id = vim.api.nvim_create_namespace("womwiki_graph")
	for _, hl in ipairs(highlights) do
		if hl.col_start and hl.col_end then
			vim.api.nvim_buf_add_highlight(buf, ns_id, hl.hl_group, hl.line, hl.col_start, hl.col_end)
		else
			vim.api.nvim_buf_add_highlight(buf, ns_id, hl.hl_group, hl.line, 0, -1)
		end
	end

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
		require("womwiki.files").wiki()
	end, keymap_opts)

	vim.keymap.set("n", "/", function()
		vim.api.nvim_win_close(win, true)

		-- Use vim.schedule to ensure picker opens after window closes
		vim.schedule(function()
			-- Show all files in picker with fuzzy search (filter as you type)
			local picker_type, picker = utils.get_picker()

			if not picker then
				vim.notify("No picker available!", vim.log.levels.ERROR)
				return
			end

			local all_files = {}
			for name, _ in pairs(graph) do
				table.insert(all_files, name .. ".md")
			end
			table.sort(all_files)

			if picker_type == "telescope" then
				require("telescope.pickers")
					.new({}, {
						prompt_title = "Search/Filter Files",
						finder = require("telescope.finders").new_table({
							results = all_files,
						}),
						sorter = require("telescope.config").values.generic_sorter({}),
						attach_mappings = function(_, map)
							map("i", "<CR>", function(prompt_bufnr)
								local selection = require("telescope.actions.state").get_selected_entry()
								require("telescope.actions").close(prompt_bufnr)
								if selection then
									utils.open_wiki_file(config.wikidir .. "/" .. selection.value)
								end
							end)
							return true
						end,
					})
					:find()
			elseif picker_type == "mini" then
				local selected = picker.start({
					source = { items = all_files, name = "Search/Filter Files" },
				})
				if selected then
					utils.open_wiki_file(config.wikidir .. "/" .. selected)
				end
			elseif picker_type == "snacks" then
				picker.picker.select(all_files, {
					prompt = "Search/Filter Files",
					format = function(item)
						return item
					end,
				}, function(selected)
					if selected then
						-- Snacks may pass item as string or table
						local filename = type(selected) == "table" and selected.text or selected
						utils.open_wiki_file(config.wikidir .. "/" .. filename)
					end
				end)
			elseif picker_type == "fzf" then
				picker.fzf_exec(all_files, {
					prompt = "Search/Filter Files> ",
					actions = {
						["default"] = function(selected)
							if selected and selected[1] then
								local filename = selected[1]
								utils.open_wiki_file(config.wikidir .. "/" .. filename)
							end
						end,
					},
				})
			end
		end) -- Close vim.schedule
	end, keymap_opts)

	vim.keymap.set("n", "e", function()
		vim.api.nvim_win_close(win, true)

		-- Use vim.schedule to ensure picker opens after window closes
		vim.schedule(function()
			-- Show details for a specific file using fuzzy picker
			local picker_type, picker = utils.get_picker()

			if not picker then
				vim.notify("No picker available!", vim.log.levels.ERROR)
				return
			end

			-- Helper to show file details in a floating window
			local function show_file_details(filename)
				-- Remove .md extension if present
				local target_file = filename:gsub("%.md$", "")

				if not graph[target_file] then
					vim.notify("File not found in graph: " .. target_file, vim.log.levels.ERROR)
					return
				end

				local data = graph[target_file]
				local info_lines = {}
				table.insert(info_lines, "╭─ File Details " .. string.rep("─", 50) .. "╮")
				table.insert(info_lines, "│ File: " .. target_file .. string.rep(" ", 59 - #target_file) .. "│")
				table.insert(
					info_lines,
					"│ Total connections: "
						.. (#data.links_to + #data.linked_from)
						.. string.rep(" ", 44 - #tostring(#data.links_to + #data.linked_from))
						.. "│"
				)
				table.insert(info_lines, "├" .. string.rep("─", 65) .. "┤")
				table.insert(
					info_lines,
					"│ Links to ("
						.. #data.links_to
						.. "):"
						.. string.rep(" ", 52 - #tostring(#data.links_to))
						.. "│"
				)
				if #data.links_to > 0 then
					for _, link in ipairs(data.links_to) do
						local line = "│   → " .. link
						table.insert(info_lines, line .. string.rep(" ", 66 - #line) .. "│")
					end
				else
					table.insert(info_lines, "│   (none)" .. string.rep(" ", 55) .. "│")
				end
				table.insert(info_lines, "├" .. string.rep("─", 65) .. "┤")
				table.insert(
					info_lines,
					"│ Linked from ("
						.. #data.linked_from
						.. "):"
						.. string.rep(" ", 49 - #tostring(#data.linked_from))
						.. "│"
				)
				if #data.linked_from > 0 then
					for _, link in ipairs(data.linked_from) do
						local line = "│   ← " .. link
						table.insert(info_lines, line .. string.rep(" ", 66 - #line) .. "│")
					end
				else
					table.insert(info_lines, "│   (none)" .. string.rep(" ", 55) .. "│")
				end
				table.insert(info_lines, "╰" .. string.rep("─", 65) .. "╯")

				-- Create and display floating window
				local detail_buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, info_lines)
				vim.bo[detail_buf].modifiable = false
				vim.bo[detail_buf].buftype = "nofile"

				local detail_width = 67
				local detail_height = math.min(#info_lines, vim.o.lines - 4)
				local detail_win = vim.api.nvim_open_win(detail_buf, true, {
					relative = "editor",
					width = detail_width,
					height = detail_height,
					col = math.floor((vim.o.columns - detail_width) / 2),
					row = math.floor((vim.o.lines - detail_height) / 2),
					style = "minimal",
					border = "rounded",
					title = " File Connections ",
					title_pos = "center",
				})

				-- Close on q or Esc
				vim.keymap.set("n", "q", function()
					vim.api.nvim_win_close(detail_win, true)
				end, { buffer = detail_buf, nowait = true, silent = true })
				vim.keymap.set("n", "<Esc>", function()
					vim.api.nvim_win_close(detail_win, true)
				end, { buffer = detail_buf, nowait = true, silent = true })
			end

			-- Build list of all files
			local all_files = {}
			for name, _ in pairs(graph) do
				table.insert(all_files, name .. ".md")
			end
			table.sort(all_files)

			-- Show in picker
			if picker_type == "telescope" then
				require("telescope.pickers")
					.new({}, {
						prompt_title = "Select File to Expand",
						finder = require("telescope.finders").new_table({
							results = all_files,
						}),
						sorter = require("telescope.config").values.generic_sorter({}),
						attach_mappings = function(_, map)
							map("i", "<CR>", function(prompt_bufnr)
								local selection = require("telescope.actions.state").get_selected_entry()
								require("telescope.actions").close(prompt_bufnr)
								if selection then
									show_file_details(selection.value)
								end
							end)
							return true
						end,
					})
					:find()
			elseif picker_type == "mini" then
				local selected = picker.start({
					source = { items = all_files, name = "Select File to Expand" },
				})
				if selected then
					show_file_details(selected)
				end
			elseif picker_type == "snacks" then
				picker.picker.select(all_files, {
					prompt = "Select File to Expand",
					format = function(item)
						return item
					end,
				}, function(selected)
					if selected then
						-- Snacks may pass item as string or table
						local filename = type(selected) == "table" and selected.text or selected
						show_file_details(filename)
					end
				end)
			elseif picker_type == "fzf" then
				picker.fzf_exec(all_files, {
					prompt = "Select File to Expand> ",
					actions = {
						["default"] = function(selected)
							if selected and selected[1] then
								vim.schedule(function()
									show_file_details(selected[1])
								end)
							end
						end,
					},
				})
			end
		end) -- Close vim.schedule
	end, keymap_opts)

	vim.keymap.set("n", "h", function()
		vim.api.nvim_win_close(win, true)
		-- Show hubs in picker
		local picker_type, picker = utils.get_picker()

		if not picker then
			vim.notify("No picker available!", vim.log.levels.ERROR)
			return
		end

		if #hubs == 0 then
			vim.notify("No hub files found (files with 3+ backlinks)", vim.log.levels.WARN)
			return
		end

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
								utils.open_wiki_file(config.wikidir .. "/" .. selection.value)
							end
						end)
						return true
					end,
				})
				:find()
		elseif picker_type == "mini" then
			local selected = picker.start({
				source = { items = hub_items, name = "Hub Files" },
			})
			if selected then
				utils.open_wiki_file(config.wikidir .. "/" .. selected)
			end
		elseif picker_type == "snacks" then
			picker.picker.select(hub_items, {
				prompt = "Hub Files",
				format = function(item)
					return item
				end,
			}, function(selected)
				if selected then
					-- Snacks may pass item as string or table
					local filename = type(selected) == "table" and selected.text or selected
					utils.open_wiki_file(config.wikidir .. "/" .. filename)
				end
			end)
		elseif picker_type == "fzf" then
			picker.fzf_exec(hub_items, {
				prompt = "Hub Files> ",
				actions = {
					["default"] = function(selected)
						if selected and selected[1] then
							local filename = selected[1]
							utils.open_wiki_file(config.wikidir .. "/" .. filename)
						end
					end,
				},
			})
		end
	end, keymap_opts)

	vim.keymap.set("n", "o", function()
		vim.api.nvim_win_close(win, true)
		-- Show orphans in picker
		local picker_type, picker = utils.get_picker()
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
									utils.open_wiki_file(config.wikidir .. "/" .. selection.value)
								end
							end)
							return true
						end,
					})
					:find()
			elseif picker_type == "mini" then
				local selected = picker.start({
					source = { items = orphan_items, name = "Orphan Files" },
				})
				if selected then
					utils.open_wiki_file(config.wikidir .. "/" .. selected)
				end
			elseif picker_type == "snacks" then
				picker.picker.select(orphan_items, {
					prompt = "Orphan Files",
					format = function(item)
						return item
					end,
				}, function(selected)
					if selected then
						-- Snacks may pass item as string or table
						local filename = type(selected) == "table" and selected.text or selected
						utils.open_wiki_file(config.wikidir .. "/" .. filename)
					end
				end)
			elseif picker_type == "fzf" then
				picker.fzf_exec(orphan_items, {
					prompt = "Orphan Files> ",
					actions = {
						["default"] = function(selected)
							if selected and selected[1] then
								local filename = selected[1]
								utils.open_wiki_file(config.wikidir .. "/" .. filename)
							end
						end,
					},
				})
			end
		end
	end, keymap_opts)
end

return M

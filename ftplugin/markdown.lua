---@type vim
local vim = vim

vim.opt_local.tabstop = 2
vim.opt_local.shiftwidth = 2
vim.opt_local.softtabstop = 2

-- Helper: Ensure filename has .md extension
local function ensure_md_extension(filename)
	if not filename:match("%.md$") then
		return filename .. ".md"
	end
	return filename
end

-- Helper: Convert wikilink name to filename based on config
local function wikilink_to_filename(link_name)
	local womwiki = require("womwiki")
	local spaces_to = womwiki.config.wikilinks.spaces_to
	local filename = link_name

	if spaces_to then
		filename = filename:gsub(" ", spaces_to)
	end

	return ensure_md_extension(filename)
end

-- Helper: Find case-insensitive matches for a filename in wiki
local function find_fuzzy_matches(target_name, wiki_root)
	local matches = {}
	local target_lower = target_name:lower():gsub("%.md$", "")

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
				local name_lower = name:lower():gsub("%.md$", "")
				if name_lower == target_lower then
					table.insert(matches, {
						path = full_path,
						relative = file_relative,
						name = name,
					})
				end
			elseif type == "directory" and name ~= ".git" then
				scan_directory(full_path, file_relative)
			end
		end
	end

	scan_directory(wiki_root)
	return matches
end

-- Convert word under cursor to link (markdown or wikilink based on config)
local function word_to_link()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local womwiki = require("womwiki")
	local link_style = womwiki.config.default_link_style or "markdown"

	-- Check if cursor is over an existing markdown link [text](url)
	for start_pos, text, url in line:gmatch("()%[([^%]]+)%]%(([^%)]+)%)") do
		local bracket_start = start_pos - 1
		local bracket_end = start_pos + #text + #url + 3
		if col >= bracket_start and col < bracket_end then
			-- Cursor is over a link, position inside the [text] part
			local text_start = start_pos
			local text_end = start_pos + #text - 1
			vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], text_start })
			vim.cmd("normal! v" .. (text_end - text_start) .. "lc")
			return
		end
	end

	-- Check if cursor is over an existing wikilink [[text]] or [[text|display]]
	for start_pos, content in line:gmatch("()%[%[([^%]]+)%]%]") do
		local bracket_start = start_pos - 1
		local bracket_end = start_pos + #content + 3
		if col >= bracket_start and col < bracket_end then
			-- Cursor is over a wikilink, extract the link part (before |)
			local link_part = content:match("^([^|]+)") or content
			local text_start = start_pos + 1 -- After [[
			local text_end = text_start + #link_part - 1
			vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], text_start })
			vim.cmd("normal! v" .. (text_end - text_start) .. "lc")
			return
		end
	end

	-- Check if cursor is over a URL (http:// or https://)
	local url_start = line:find("https?://", 1)
	while url_start do
		-- Find end of URL (space, closing paren, or end of line)
		local url_end = line:find("[%s%)>]", url_start) or (#line + 1)
		url_end = url_end - 1

		if col >= url_start - 1 and col < url_end then
			-- Cursor is over a URL - always use markdown format for URLs
			local url = line:sub(url_start, url_end)
			vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], url_start - 1 })
			vim.cmd("normal! v" .. (url_end - url_start) .. "lc[](" .. url .. ")")
			vim.cmd("normal! F[li")
			return
		end

		url_start = line:find("https?://", url_end + 1)
	end

	-- Not over a link or URL, convert word to link
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.notify("No word under cursor", vim.log.levels.WARN)
		return
	end

	if link_style == "wikilink" then
		vim.cmd("normal! ciw[[" .. word .. "]]")
		vim.cmd("normal! F[lli")
	else
		vim.cmd("normal! ciw[" .. word .. "]()")
		vim.cmd("normal! i")
	end
end

-- Toggle markdown checkbox on line(s)
local function toggle_markdown_checkbox()
	local start_line = vim.fn.line(".")
	local end_line = vim.fn.line(".")

	-- Check if in visual mode
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		start_line = vim.fn.line("v")
		end_line = vim.fn.line(".")
		if start_line > end_line then
			start_line, end_line = end_line, start_line
		end
	end

	for lnum = start_line, end_line do
		local line = vim.fn.getline(lnum)
		local indent = line:match("^(%s*)")
		local content = line:sub(#indent + 1)

		-- Detect existing list marker (- or *)
		local marker = "-"
		local has_marker = false
		if content:match("^[%-%*] ") then
			marker = content:sub(1, 1)
			has_marker = true
		end

		-- Check if line already has a checkbox
		if content:match("^[%-%*] %[ %] ") then
			-- Toggle to checked
			local new_line = indent .. content:gsub("^([%-%*]) %[ %] ", "%1 [x] ")
			vim.fn.setline(lnum, new_line)
		elseif content:match("^[%-%*] %[x%] ") or content:match("^[%-%*] %[X%] ") then
			-- Remove checkbox, keep marker and content
			local new_line = indent .. content:gsub("^([%-%*]) %[[xX]%] ", "%1 ")
			vim.fn.setline(lnum, new_line)
		else
			-- Add unchecked checkbox
			if has_marker then
				-- Already has - or *, insert checkbox after marker
				local rest = content:sub(3) -- Everything after "- " or "* "
				vim.fn.setline(lnum, indent .. marker .. " [ ] " .. rest)
			else
				-- No marker, add default - with checkbox
				if content == "" then
					vim.fn.setline(lnum, indent .. "- [ ] ")
				else
					vim.fn.setline(lnum, indent .. "- [ ] " .. content)
				end
			end
		end
	end

	-- Exit visual mode if we were in it
	if mode == "v" or mode == "V" or mode == "\22" then
		vim.cmd("normal! \27")
	end
end

-- Follow markdown link under cursor
local function follow_markdown_link()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local womwiki = require("womwiki")
	local wiki_root = womwiki.wikidir
	local current_dir = vim.fn.expand("%:p:h")

	-- Helper to open file and jump to line
	local function open_and_jump(path, line_anchor)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		vim.b.womwiki = true
		if wiki_root then
			vim.cmd("lcd " .. vim.fn.fnameescape(wiki_root))
		end
		-- Jump to line if anchor present
		if line_anchor then
			local target_line = tonumber(line_anchor)
			if target_line then
				vim.api.nvim_win_set_cursor(0, { target_line, 0 })
				vim.cmd("normal! zz") -- Center the line
			end
		end
	end

	-- Helper to create a new file with confirmation
	local function create_file_with_confirm(file_path, display_name)
		local new_path = wiki_root and (wiki_root .. "/" .. file_path) or (current_dir .. "/" .. file_path)

		vim.ui.select({ "Create '" .. display_name .. "'", "Cancel" }, {
			prompt = "File does not exist:",
		}, function(choice)
			if choice and choice:match("^Create") then
				-- Create parent directories if needed
				local dir = vim.fn.fnamemodify(new_path, ":h")
				vim.fn.mkdir(dir, "p")

				-- Create file with basic header
				local new_file = io.open(new_path, "w")
				if new_file then
					local title = display_name:gsub("%.md$", ""):gsub("[_-]", " ")
					new_file:write("# " .. title .. "\n\n")
					new_file:close()
					open_and_jump(new_path)
				end
			end
		end)
	end

	-- Helper to handle "did you mean" with fuzzy matches
	local function handle_fuzzy_matches(target_name, matches, display_name)
		local options = {}
		for _, match in ipairs(matches) do
			table.insert(options, "Open '" .. match.relative .. "'")
		end
		table.insert(options, "Create '" .. display_name .. "'")
		table.insert(options, "Cancel")

		vim.ui.select(options, {
			prompt = "Did you mean?",
		}, function(choice)
			if not choice then
				return
			end

			if choice == "Cancel" then
				return
			elseif choice:match("^Create") then
				create_file_with_confirm(wikilink_to_filename(target_name), display_name)
			else
				-- Find which match was selected
				for _, match in ipairs(matches) do
					if choice == "Open '" .. match.relative .. "'" then
						open_and_jump(match.path)
						return
					end
				end
			end
		end)
	end

	-- Check for wikilinks first: [[link]] or [[link|display]]
	if womwiki.config.wikilinks.enabled then
		for start_pos, link_content in line:gmatch("()%[%[([^%]]+)%]%]") do
			local bracket_start = start_pos - 1
			local bracket_end = start_pos + #link_content + 3 -- [[ + content + ]]

			if col >= bracket_start and col < bracket_end then
				-- Parse [[link|display]] format
				local link_target, _ = link_content:match("^([^|]+)|(.+)$")
				if not link_target then
					link_target = link_content
				end

				local filename = wikilink_to_filename(link_target)

				-- Try to find exact match (case-sensitive)
				local resolved_path = wiki_root and (wiki_root .. "/" .. filename) or (current_dir .. "/" .. filename)
				local file = io.open(resolved_path, "r")
				if file then
					file:close()
					open_and_jump(resolved_path)
					return
				end

				-- Try in subdirectories (exact match)
				if wiki_root then
					local function find_exact_in_subdirs(dir)
						local handle = vim.uv.fs_scandir(dir)
						if not handle then
							return nil
						end

						while true do
							local name, type = vim.uv.fs_scandir_next(handle)
							if not name then
								break
							end

							local full_path = dir .. "/" .. name
							if type == "file" and name == filename then
								return full_path
							elseif type == "directory" and name ~= ".git" then
								local found = find_exact_in_subdirs(full_path)
								if found then
									return found
								end
							end
						end
						return nil
					end

					local exact_match = find_exact_in_subdirs(wiki_root)
					if exact_match then
						open_and_jump(exact_match)
						return
					end
				end

				-- No exact match - look for case-insensitive matches
				local fuzzy_matches = find_fuzzy_matches(filename, wiki_root or current_dir)

				if #fuzzy_matches > 0 then
					-- Found fuzzy matches - ask "did you mean?"
					handle_fuzzy_matches(link_target, fuzzy_matches, filename)
				else
					-- No matches at all - offer to create
					create_file_with_confirm(filename, filename)
				end
				return
			end
		end
	end

	-- Find all markdown links in the line [text](url)
	for start_pos, text, url in line:gmatch("()%[([^%]]+)%]%(([^%)]+)%)") do
		local bracket_start = start_pos - 1
		local bracket_end = start_pos + #text + #url + 3

		if col >= bracket_start and col < bracket_end then
			-- Check if it's a URL
			if url:match("^https?://") then
				-- Open URL in browser - handle WSL specially
				local is_wsl = vim.fn.has("wsl") == 1 or vim.fn.exists("$WSL_DISTRO_NAME") == 1

				if is_wsl then
					vim.fn.system({ "cmd.exe", "/c", "start", url })
				else
					vim.ui.open(url)
				end
				return
			end

			-- Parse line anchor (#L42) from URL if present
			local file_path, line_anchor = url:match("^(.-)#L(%d+)$")
			if not file_path then
				file_path = url
				line_anchor = nil
			end

			-- Try relative to current file first
			local resolved_path = current_dir .. "/" .. ensure_md_extension(file_path)

			-- Check if file exists relative to current file
			local file = io.open(resolved_path, "r")
			if file then
				file:close()
				open_and_jump(resolved_path, line_anchor)
				return
			end

			-- Try relative to wiki root
			if wiki_root then
				resolved_path = wiki_root .. "/" .. ensure_md_extension(file_path)

				file = io.open(resolved_path, "r")
				if file then
					file:close()
					open_and_jump(resolved_path, line_anchor)
					return
				end
			end

			-- Try as absolute path (for links to files outside wiki)
			resolved_path = ensure_md_extension(file_path)
			file = io.open(resolved_path, "r")
			if file then
				file:close()
				open_and_jump(resolved_path, line_anchor)
				return
			end

			-- File doesn't exist - offer to create with confirmation
			create_file_with_confirm(ensure_md_extension(file_path), file_path)
			return
		end
	end

	-- No link found, fallback to vim's default gf behavior
	vim.notify("No markdown link under cursor", vim.log.levels.WARN)
end

vim.keymap.set("n", "<leader>ml", word_to_link, {
	buffer = true,
	desc = "Convert word to link (respects default_link_style)",
	silent = true,
})

vim.keymap.set({ "n", "v" }, "<leader>mc", toggle_markdown_checkbox, {
	buffer = true,
	desc = "Toggle markdown checkbox",
	silent = true,
})

vim.keymap.set("n", "gf", follow_markdown_link, {
	buffer = true,
	desc = "Follow markdown link",
	silent = true,
})

vim.keymap.set("n", "<CR>", follow_markdown_link, {
	buffer = true,
	desc = "Follow markdown link",
	silent = true,
})

-- Setup link autocompletion
local has_womwiki, womwiki = pcall(require, "womwiki")
if has_womwiki then
	womwiki.setup_completion()
end

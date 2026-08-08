---@type vim
local vim = vim
local womwiki_config = require("womwiki.config")
local patterns = womwiki_config.patterns

local function is_wiki_buffer()
	if not womwiki_config.is_valid() then
		return false
	end

	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		return false
	end

	local resolved = vim.uv.fs_realpath(filepath) or vim.fn.fnamemodify(filepath, ":p")
	return resolved == womwiki_config.wikidir or vim.startswith(resolved, womwiki_config.wikidir .. "/")
end

local is_wiki = is_wiki_buffer()

if is_wiki then
	vim.b.womwiki = true
end

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
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local womwiki = require("womwiki")
	local link_style = womwiki.config.default_link_style or "markdown"

	-- Check if cursor is over an existing markdown link [text](url)
	for start_pos, text, url in line:gmatch("()%[([^%]]+)%]%(([^%)]*)%)") do
		local bracket_start = start_pos - 1
		local bracket_end = start_pos + #text + #url + 3
		if col >= bracket_start and col < bracket_end then
			-- Skip URL links — can't convert to wikilink
			if url:match(patterns.URL_HTTP) then
				vim.notify("Cannot convert URL link to wikilink", vim.log.levels.WARN)
				return
			end
			-- Convert markdown link → wikilink: [text](file.md) → [[file|text]] if text ~= file, else [[file]]
			local link_name = url ~= "" and url:gsub("%.md$", "") or text
			local replacement
			if text == link_name then
				replacement = "[[" .. link_name .. "]]"
			else
				replacement = "[[" .. link_name .. "|" .. text .. "]]"
			end
			local new_line = line:sub(1, bracket_start) .. replacement .. line:sub(bracket_end + 1)
			vim.api.nvim_set_current_line(new_line)
			-- Position cursor inside the wikilink
			vim.api.nvim_win_set_cursor(0, { row, bracket_start + 2 })
			return
		end
	end

	-- Check if cursor is over an existing wikilink [[text]] or [[text|display]]
	for start_pos, content in line:gmatch("()%[%[([^%]]+)%]%]") do
		local bracket_start = start_pos - 1
		local bracket_end = start_pos + #content + 3
		if col >= bracket_start and col < bracket_end then
			-- Convert wikilink → markdown link: [[page]] or [[page|display]] → [display](page.md)
			local link_part = vim.trim(content:match("^([^|]+)") or content)
			local display = vim.trim(content:match("^[^|]+|(.+)$") or link_part)
			local file_path = ensure_md_extension(link_part)
			local replacement = "[" .. display .. "](" .. file_path .. ")"
			local new_line = line:sub(1, bracket_start) .. replacement .. line:sub(bracket_end + 1)
			vim.api.nvim_set_current_line(new_line)
			-- Position cursor inside the markdown link text
			vim.api.nvim_win_set_cursor(0, { row, bracket_start + 1 })
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
			vim.api.nvim_win_set_cursor(0, { row, url_start - 1 })
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
-- Cycle: plain list → [ ] → [-] → [x] → [ ]
-- Non-list lines and [>] forwarded items are no-ops
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

		-- Detect list marker: - , * , or numbered (1. , 2. , etc.)
		local marker, marker_len
		if content:match("^[%-%*] ") then
			marker = content:sub(1, 1)
			marker_len = 2
		elseif content:match("^%d+%. ") then
			marker = content:match("^(%d+%.)")
			marker_len = #marker + 1
		end

		if marker then
			local is_forwarded = content:match("^[%-%*] %[>%] ") or content:match("^%d+%. %[>%] ")
			if not is_forwarded then
				if content:match("^[%-%*] %[ %] ") or content:match("^%d+%. %[ %] ") then
					-- [ ] → [-]
					local new_line = indent .. content:gsub("^(.-%[) (%].)", "%1-%2")
					vim.fn.setline(lnum, new_line)
				elseif content:match("^[%-%*] %[%-%] ") or content:match("^%d+%. %[%-%] ") then
					-- [-] → [x]
					local new_line = indent .. content:gsub("^(.-%[)%-(%].)", "%1x%2")
					vim.fn.setline(lnum, new_line)
				elseif content:match("^[%-%*] %[[xX]%] ") or content:match("^%d+%. %[[xX]%] ") then
					-- [x] → [ ]
					local new_line = indent .. content:gsub("^(.-%[)[xX](%].)", "%1 %2")
					vim.fn.setline(lnum, new_line)
				else
					-- List item without checkbox: add [ ]
					local rest = content:sub(marker_len + 1)
					vim.fn.setline(lnum, indent .. marker .. " [ ] " .. rest)
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
	local files = require("womwiki.files")
	local wiki_root = womwiki.wikidir
	local current_dir = vim.fn.expand("%:p:h")

	-- Jump to a 1-based line within the current buffer/window (bounds-checked)
	local function jump_to_line(target_line)
		target_line = tonumber(target_line)
		if not target_line then
			return
		end
		if target_line < 1 or target_line > vim.api.nvim_buf_line_count(0) then
			vim.notify("Line out of range: #L" .. target_line, vim.log.levels.WARN)
			return
		end
		vim.api.nvim_win_set_cursor(0, { target_line, 0 })
		vim.cmd("normal! zz") -- Center the line
	end

	-- Helper to open file and jump to a 1-based line
	local function open_and_jump(path, target_line)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		if wiki_root then
			vim.cmd("lcd " .. vim.fn.fnameescape(wiki_root))
		end
		jump_to_line(target_line)
	end

	-- Resolve a heading slug to a 1-based line in the current buffer (respects unsaved edits)
	local function find_heading_line_in_buffer(slug)
		if not slug or slug == "" then
			return nil
		end
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local lower = slug:lower()
		local ci_match
		for lnum, l in ipairs(lines) do
			local level, text = l:match("^(#+)%s+(.+)$")
			if level and text then
				local s = files.slugify(text)
				if s == slug then
					return lnum
				end
				if not ci_match and s:lower() == lower then
					ci_match = lnum
				end
			end
		end
		return ci_match
	end

	-- Split a link target into its file part and anchor.
	-- Splits on the first '#' so the file part never includes a fragment;
	-- a trailing '#' yields an empty (no-op) anchor rather than a filename.
	-- @return string file_part, string|nil anchor, boolean has_anchor, string|nil line_anchor
	local function split_anchor(target)
		local file_part, anchor
		local hash = target:find("#", 1, true)
		if hash then
			file_part = target:sub(1, hash - 1)
			anchor = target:sub(hash + 1)
		else
			file_part = target
			anchor = nil
		end
		local has_anchor = anchor ~= nil and anchor ~= ""
		local line_anchor = has_anchor and anchor:match("^L(%d+)$") or nil
		return file_part, anchor, has_anchor, line_anchor
	end

	-- Jump within the current buffer for a pure in-page anchor ([text](#x) / [[#x]]).
	local function jump_in_page(anchor, has_anchor, line_anchor)
		if not has_anchor then
			return -- bare "#": placeholder link, no target
		end
		if line_anchor then
			jump_to_line(tonumber(line_anchor))
		else
			local target = find_heading_line_in_buffer(anchor)
			if target then
				jump_to_line(target)
			else
				vim.notify("Heading not found: #" .. anchor, vim.log.levels.WARN)
			end
		end
	end

	-- Canonicalize a path for identity comparison: resolve symlinks (consistent with how
	-- config.wikidir is resolved) and fall back to an absolute path when realpath fails.
	local function canonical_path(p)
		if not p or p == "" then
			return nil
		end
		local abs = vim.fn.fnamemodify(p, ":p")
		return vim.uv.fs_realpath(abs) or abs
	end

	-- Open a resolved file and jump to its anchor (line number or heading slug).
	-- If the link points at the current buffer, jump in place so unsaved edits are
	-- respected and the buffer is not reloaded.
	local function open_with_anchor(resolved_path, anchor, has_anchor, line_anchor)
		local target_path = canonical_path(resolved_path)
		local current_path = canonical_path(vim.api.nvim_buf_get_name(0))
		if target_path and current_path and target_path == current_path then
			jump_in_page(anchor, has_anchor, line_anchor)
			return
		end
		local target
		if line_anchor then
			target = tonumber(line_anchor)
		elseif has_anchor then
			target = files.find_heading_line(resolved_path, anchor)
			if not target then
				vim.notify("Heading not found: #" .. anchor, vim.log.levels.WARN)
			end
		end
		open_and_jump(resolved_path, target)
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
	local function handle_fuzzy_matches(target_name, matches, display_name, anchor, has_anchor, line_anchor)
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
						open_with_anchor(match.path, anchor, has_anchor, line_anchor)
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
					link_target = vim.trim(link_content)
				else
					link_target = vim.trim(link_target)
				end

				-- Handle special navigation links for daily notes
				if link_target == "« Prev" then
					require("womwiki.daily").prev()
					return
				elseif link_target == "Next »" then
					require("womwiki.daily").next()
					return
				end

				-- Split off any heading/line anchor ([[#x]] or [[page#x]])
				local file_part, anchor, has_anchor, line_anchor = split_anchor(link_target)

				-- Pure in-page anchor: [[#heading]] -> jump within current buffer
				if file_part == "" and anchor ~= nil then
					jump_in_page(anchor, has_anchor, line_anchor)
					return
				end

				local filename = wikilink_to_filename(file_part)

				-- Try to find exact match (case-sensitive)
				local resolved_path = wiki_root and (wiki_root .. "/" .. filename) or (current_dir .. "/" .. filename)
				local file = io.open(resolved_path, "r")
				if file then
					file:close()
					open_with_anchor(resolved_path, anchor, has_anchor, line_anchor)
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
						open_with_anchor(exact_match, anchor, has_anchor, line_anchor)
						return
					end
				end

				-- No exact match - look for case-insensitive matches
				local fuzzy_matches = find_fuzzy_matches(filename, wiki_root or current_dir)

				if #fuzzy_matches > 0 then
					-- Found fuzzy matches - ask "did you mean?"
					handle_fuzzy_matches(file_part, fuzzy_matches, filename, anchor, has_anchor, line_anchor)
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
			if url:match(patterns.URL_HTTP) then
				-- Open URL in browser - handle WSL specially
				local is_wsl = vim.fn.has("wsl") == 1 or vim.fn.exists("$WSL_DISTRO_NAME") == 1

				if is_wsl then
					vim.fn.system({ "cmd.exe", "/c", "start", url })
				else
					vim.ui.open(url)
				end
				return
			end

			-- Parse anchor from URL: #L<num> (line) or #<slug> (heading)
			local file_path, anchor, has_anchor, line_anchor = split_anchor(url)

			-- Pure in-page anchor: [text](#heading) / [text](#L42) -> jump within current buffer
			if file_path == "" and anchor ~= nil then
				jump_in_page(anchor, has_anchor, line_anchor)
				return
			end

			-- Try relative to current file first
			local resolved_path = current_dir .. "/" .. ensure_md_extension(file_path)

			-- Check if file exists relative to current file
			local file = io.open(resolved_path, "r")
			if file then
				file:close()
				open_with_anchor(resolved_path, anchor, has_anchor, line_anchor)
				return
			end

			-- Try relative to wiki root
			if wiki_root then
				resolved_path = wiki_root .. "/" .. ensure_md_extension(file_path)

				file = io.open(resolved_path, "r")
				if file then
					file:close()
					open_with_anchor(resolved_path, anchor, has_anchor, line_anchor)
					return
				end
			end

			-- Try as absolute path (for links to files outside wiki)
			resolved_path = ensure_md_extension(file_path)
			file = io.open(resolved_path, "r")
			if file then
				file:close()
				open_with_anchor(resolved_path, anchor, has_anchor, line_anchor)
				return
			end

			-- File doesn't exist - offer to create with confirmation
			create_file_with_confirm(ensure_md_extension(file_path), file_path)
			return
		end
	end

	-- No link found; this mapping is active only for wiki Markdown buffers.
	vim.notify("No markdown link under cursor", vim.log.levels.WARN)
end

if is_wiki then
	vim.keymap.set("n", "<leader>ml", word_to_link, {
		buffer = true,
		desc = "Convert word to link / cycle link format",
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
end

-- Setup link autocompletion
local has_womwiki, womwiki = pcall(require, "womwiki")
if has_womwiki then
	womwiki.setup_completion()
end

-- Setup tag highlighting
if has_womwiki and womwiki.config.tags and womwiki.config.tags.enabled then
	-- Highlight inline #tags (but not in code blocks or URLs)
	vim.fn.matchadd("WomwikiTag", "\\v(^|\\s)#[a-zA-Z0-9_-]+")
end

-- Auto-configure table.vim for wiki buffers
if vim.b.womwiki then
	local has_table_vim = pcall(require, "table_vim")
	if has_table_vim then
		vim.fn["table#SetBufferConfig"]({
			style = "markdown",
			options = {
				default_alignment = "center",
				multiline = "auto",
			},
		})
	end
end

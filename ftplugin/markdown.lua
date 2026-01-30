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

-- Convert word under cursor to markdown link
local function word_to_markdown_link()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]

	-- Check if cursor is over an existing markdown link
	-- Pattern matches [text](url) format
	local text_start = nil
	local text_end = nil

	for start_pos, text, url in line:gmatch("()%[([^%]]+)%]%(([^%)]+)%)") do
		local bracket_start = start_pos - 1
		local bracket_end = start_pos + #text + #url + 3
		if col >= bracket_start and col < bracket_end then
			-- Cursor is over a link, position inside the [text] part
			text_start = start_pos
			text_end = start_pos + #text - 1
			break
		end
	end

	if text_start then
		-- Move cursor to start of link text and enter select mode
		vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], text_start })
		vim.cmd("normal! v" .. (text_end - text_start) .. "lc")
		return
	end

	-- Check if cursor is over a URL (http:// or https://)
	local url_start = line:find("https?://", 1)
	while url_start do
		-- Find end of URL (space, closing paren, or end of line)
		local url_end = line:find("[%s%)>]", url_start) or (#line + 1)
		url_end = url_end - 1

		if col >= url_start - 1 and col < url_end then
			-- Cursor is over a URL
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

	vim.cmd("normal! ciw[" .. word .. "]()")
	vim.cmd("normal! i")
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

			-- It's a file path - resolve relative to current file or wiki root
			local current_file = vim.fn.expand("%:p:h")
			local womwiki = require("womwiki")
			local wiki_root = womwiki.wikidir

			-- Helper to open file and jump to line
			local function open_and_jump(path)
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

			-- Try relative to current file first
			local resolved_path = current_file .. "/" .. ensure_md_extension(file_path)

			-- Check if file exists relative to current file
			local file = io.open(resolved_path, "r")
			if file then
				file:close()
				open_and_jump(resolved_path)
				return
			end

			-- Try relative to wiki root
			if wiki_root then
				resolved_path = wiki_root .. "/" .. ensure_md_extension(file_path)

				file = io.open(resolved_path, "r")
				if file then
					file:close()
					open_and_jump(resolved_path)
					return
				end
			end

			-- Try as absolute path (for links to files outside wiki)
			resolved_path = ensure_md_extension(file_path)
			file = io.open(resolved_path, "r")
			if file then
				file:close()
				open_and_jump(resolved_path)
				return
			end

			-- File doesn't exist - offer to create it (only for wiki-like paths)
			vim.ui.input({
				prompt = 'File does not exist. Create "' .. file_path .. '"? (y/N): ',
			}, function(confirm)
				if confirm and confirm:lower() == "y" then
					-- Create in same directory as current file
					local new_path = current_file .. "/" .. ensure_md_extension(file_path)

					-- Create file with basic header
					local new_file = io.open(new_path, "w")
					if new_file then
						local title = file_path:gsub("%.md$", ""):gsub("[_-]", " ")
						new_file:write("# " .. title .. "\n\n")
						new_file:close()
						open_and_jump(new_path)
					end
				end
			end)
			return
		end
	end

	-- No link found, fallback to vim's default gf behavior
	vim.notify("No markdown link under cursor", vim.log.levels.WARN)
end

vim.keymap.set("n", "<leader>ml", word_to_markdown_link, {
	buffer = true,
	desc = "Convert word to markdown link",
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

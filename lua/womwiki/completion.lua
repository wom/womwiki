-- Shared completion logic for womwiki
-- Used by both nvim-cmp and blink.cmp adapters

local M = {}

-- LSP CompletionItemKind values (same for both frameworks)
M.Kind = {
	File = 17,
	Reference = 18,
}

--- Parse line to detect markdown link context
--- @param line string Line content before cursor
--- @return string|nil typed Text typed after trigger
--- @return boolean in_link Whether cursor is inside a link
--- @return string|nil link_type "markdown" or "wikilink"
function M.parse_link_context(line)
	-- Check for wikilink first: [[
	local wikilink_start = line:match("%[%[[^%]]*$")
	if wikilink_start then
		-- Get what's typed after [[
		local typed = line:match("%[%[([^%]|]*)$") or ""
		return typed, true, "wikilink"
	end

	-- Check if we're inside a markdown link: [text](
	local link_start = line:match("%]%([^)]*$")
	if not link_start then
		return nil, false, nil
	end

	-- Get what's typed after ](
	local typed = line:match("%]%(([^)]*)$") or ""
	return typed, true, "markdown"
end

--- Build completion items for wiki files and headings
--- @param line string Line content before cursor
--- @return table result { items = {...}, is_incomplete = false, link_type = "markdown"|"wikilink"|nil }
function M.get_items(line)
	local typed, in_link, link_type = M.parse_link_context(line)

	if not in_link then
		return { items = {}, is_incomplete = false, link_type = nil }
	end

	local womwiki = require("womwiki")
	local items = {}
	local files = womwiki.get_wiki_files()

	-- Check if user is typing a heading reference (contains #)
	local file_part, heading_part = typed:match("^(.-)#(.*)$")

	if file_part and womwiki.config.completion.include_headings then
		-- Complete headings for the specified file
		local target_file = nil

		for _, file in ipairs(files) do
			if file.path == file_part or file.path == file_part .. ".md" then
				target_file = file.full_path
				break
			end
		end

		if target_file then
			local headings = womwiki.get_file_headings(target_file)
			for _, heading in ipairs(headings) do
				local indent = string.rep("  ", heading.level - 1)
				table.insert(items, {
					label = file_part .. "#" .. heading.slug,
					kind = M.Kind.Reference,
					detail = indent .. heading.text,
					sortText = string.format("%02d-%s", heading.level, heading.slug),
					filterText = file_part .. "#" .. heading.slug .. " " .. heading.text,
				})
			end
		end
	else
		-- Complete file paths
		for _, file in ipairs(files) do
			-- For wikilinks, use just the filename without extension
			-- For markdown links, use the path with extension
			local label = file.path
			local insert_text = file.path
			if link_type == "wikilink" then
				-- Strip .md extension for wikilinks if present
				insert_text = file.path:gsub("%.md$", "")
				label = insert_text
			end

			table.insert(items, {
				label = label,
				kind = M.Kind.File,
				detail = file.title,
				sortText = file.path,
				filterText = file.path .. " " .. file.title,
				insertText = insert_text,
				-- Add closing ]] for wikilinks
				insertTextSuffix = link_type == "wikilink" and "]]" or nil,
			})
			if #items >= womwiki.config.completion.max_results then
				break
			end
		end
	end

	return { items = items, is_incomplete = false, link_type = link_type }
end

--- Get trigger characters for completion
--- @return string[]
function M.get_trigger_characters()
	return { "(", "[" }
end

--- Check if completion should be available
--- @return boolean
function M.is_available()
	return vim.bo.filetype == "markdown"
end

return M

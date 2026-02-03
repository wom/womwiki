-- blink.cmp source for womwiki link completion
-- Thin adapter over womwiki.completion shared module

--- @class blink.cmp.Source
local source = {}

function source.new(opts)
	local self = setmetatable({}, { __index = source })
	self.opts = opts or {}
	return self
end

function source:enabled()
	return require("womwiki.completion").is_available()
end

function source:get_trigger_characters()
	return require("womwiki.completion").get_trigger_characters()
end

function source:get_completions(ctx, callback)
	local line = ctx.line
	local cursor_col = ctx.cursor[2]
	local line_before_cursor = line:sub(1, cursor_col)

	local completion = require("womwiki.completion")
	local result = completion.get_items(line_before_cursor)

	-- For wikilinks, add ]] suffix to insertText
	local items = {}
	for _, item in ipairs(result.items) do
		local new_item = vim.deepcopy(item)
		if result.link_type == "wikilink" and item.insertTextSuffix then
			-- Append ]] when completing wikilinks
			new_item.insertText = (item.insertText or item.label) .. item.insertTextSuffix
		end
		table.insert(items, new_item)
	end

	callback({
		items = items,
		is_incomplete_forward = result.is_incomplete,
		is_incomplete_backward = result.is_incomplete,
	})
end

return source

-- nvim-cmp source for womwiki link completion
-- Thin adapter over womwiki.completion shared module

local source = {}

source.new = function()
	return setmetatable({}, { __index = source })
end

source.get_keyword_pattern = function()
	-- Match text after ](
	return [[\%(\]\(\)\@<=\f*]]
end

source.get_trigger_characters = function()
	return require("womwiki.completion").get_trigger_characters()
end

source.is_available = function()
	return require("womwiki.completion").is_available()
end

source.complete = function(self, params, callback)
	local line = params.context.cursor_before_line
	local completion = require("womwiki.completion")
	local result = completion.get_items(line)

	callback({ items = result.items, isIncomplete = result.is_incomplete })
end

return source

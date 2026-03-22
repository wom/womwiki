local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

local completion = require("womwiki.completion")

local T = new_set()

--------------------------------------------------------------------------------
-- parse_link_context
--------------------------------------------------------------------------------

local parse = new_set()
T["parse_link_context"] = parse

parse["detects markdown link"] = function()
	local typed, in_link, link_type = completion.parse_link_context("[text](file")
	expect.equality(typed, "file")
	expect.equality(in_link, true)
	expect.equality(link_type, "markdown")
end

parse["detects markdown link with path"] = function()
	local typed, in_link, link_type = completion.parse_link_context("[text](path/to/file")
	expect.equality(typed, "path/to/file")
	expect.equality(in_link, true)
	expect.equality(link_type, "markdown")
end

parse["detects markdown link with empty typed"] = function()
	local typed, in_link, link_type = completion.parse_link_context("[text](")
	expect.equality(typed, "")
	expect.equality(in_link, true)
	expect.equality(link_type, "markdown")
end

parse["detects wikilink"] = function()
	local typed, in_link, link_type = completion.parse_link_context("text [[wiki")
	expect.equality(typed, "wiki")
	expect.equality(in_link, true)
	expect.equality(link_type, "wikilink")
end

parse["detects wikilink with empty typed"] = function()
	local typed, in_link, link_type = completion.parse_link_context("[[")
	expect.equality(typed, "")
	expect.equality(in_link, true)
	expect.equality(link_type, "wikilink")
end

parse["detects wikilink with spaces"] = function()
	local typed, in_link, link_type = completion.parse_link_context("text [[my page")
	expect.equality(typed, "my page")
	expect.equality(in_link, true)
	expect.equality(link_type, "wikilink")
end

parse["detects tag"] = function()
	local typed, in_link, link_type = completion.parse_link_context("text #tag")
	expect.equality(typed, "tag")
	expect.equality(in_link, true)
	expect.equality(link_type, "tag")
end

parse["detects tag with dashes and underscores"] = function()
	local typed, in_link, link_type = completion.parse_link_context("text #my-tag_here")
	expect.equality(typed, "my-tag_here")
	expect.equality(in_link, true)
	expect.equality(link_type, "tag")
end

parse["detects empty tag after hash"] = function()
	local typed, in_link, link_type = completion.parse_link_context("text #")
	expect.equality(typed, "")
	expect.equality(in_link, true)
	expect.equality(link_type, "tag")
end

parse["rejects heading as tag"] = function()
	local typed, in_link, _ = completion.parse_link_context("# heading")
	expect.equality(in_link, false)
	expect.equality(typed, nil)
end

parse["rejects multi-level heading as tag"] = function()
	local typed, in_link, _ = completion.parse_link_context("## heading")
	expect.equality(in_link, false)
	expect.equality(typed, nil)
end

parse["returns nil for plain text"] = function()
	local typed, in_link, link_type = completion.parse_link_context("just plain text")
	expect.equality(typed, nil)
	expect.equality(in_link, false)
	expect.equality(link_type, nil)
end

--------------------------------------------------------------------------------
-- get_trigger_characters
--------------------------------------------------------------------------------

T["get_trigger_characters"] = new_set()

T["get_trigger_characters"]["returns expected triggers"] = function()
	local triggers = completion.get_trigger_characters()
	expect.equality(type(triggers), "table")
	expect.equality(#triggers, 3)
	-- Should contain (, [, #
	local set = {}
	for _, c in ipairs(triggers) do
		set[c] = true
	end
	expect.equality(set["("], true)
	expect.equality(set["["], true)
	expect.equality(set["#"], true)
end

return T

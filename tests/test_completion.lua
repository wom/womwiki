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

T["get_items"] = new_set()

T["get_items"]["reports initial wiki indexing instead of an empty completion menu"] = function()
	local config = require("womwiki.config")
	local files = require("womwiki.files")
	local old_config = config.config
	local old_wikidir = config.wikidir
	local old_dailydir = config.dailydir
	local old_cache = files.cache
	local wiki_dir = vim.fn.tempname()

	vim.fn.mkdir(wiki_dir, "p")
	vim.fn.writefile({ "# Note" }, wiki_dir .. "/note.md")
	config.setup({ path = wiki_dir })
	files.cache = { files = {}, last_scan = 0, ttl = 300, loading = false, dirty_during_scan = false, scan_count = 0, initial_scan_complete = false, callbacks = {} }

	local result = completion.get_items("[[")
	expect.equality(result.is_incomplete, true)
	expect.equality(result.items[1].label, "womwiki: indexing wiki…")

	vim.wait(1000, function()
		return not files.cache.loading
	end, 10)
	files.cache = old_cache
	config.config = old_config
	config.wikidir = old_wikidir
	config.dailydir = old_dailydir
	vim.fn.delete(wiki_dir, "rf")
end

T["get_items"]["reports initial tag indexing as incomplete"] = function()
	local womwiki = require("womwiki")
	local old_get_all_tags = womwiki.get_all_tags
	womwiki.get_all_tags = function()
		return {}, true
	end

	local result = completion.get_items("text #")
	expect.equality(result.is_incomplete, true)
	expect.equality(result.items[1].label, "womwiki: indexing tags…")

	womwiki.get_all_tags = old_get_all_tags
end

return T

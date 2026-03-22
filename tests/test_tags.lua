local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

-- Setup womwiki config so tags module works
require("womwiki.config").setup({ path = "/tmp/test-wiki" })
local tags = require("womwiki.tags")

local fixtures = vim.fn.getcwd() .. "/tests/fixtures"

local T = new_set()

--------------------------------------------------------------------------------
-- parse_frontmatter
--------------------------------------------------------------------------------

local fm = new_set()
T["parse_frontmatter"] = fm

fm["parses inline tags array"] = function()
	local result = tags.parse_frontmatter(fixtures .. "/frontmatter_inline.md")
	expect.no_equality(result, nil)
	table.sort(result.tags)
	expect.equality(result.tags, { "alpha", "beta", "gamma" })
end

fm["parses multiline tags list"] = function()
	local result = tags.parse_frontmatter(fixtures .. "/frontmatter_list.md")
	expect.no_equality(result, nil)
	table.sort(result.tags)
	expect.equality(result.tags, { "alpha", "beta", "gamma" })
end

fm["returns nil for file without frontmatter"] = function()
	local result = tags.parse_frontmatter(fixtures .. "/basic.md")
	expect.equality(result, nil)
end

fm["returns nil for empty file"] = function()
	local result = tags.parse_frontmatter(fixtures .. "/empty.md")
	expect.equality(result, nil)
end

fm["returns nil for nonexistent file"] = function()
	local result = tags.parse_frontmatter(fixtures .. "/does_not_exist.md")
	expect.equality(result, nil)
end

--------------------------------------------------------------------------------
-- get_inline_tags
--------------------------------------------------------------------------------

local inline = new_set()
T["get_inline_tags"] = inline

inline["extracts inline tags"] = function()
	local result = tags.get_inline_tags(fixtures .. "/inline_tags.md")
	local set = {}
	for _, tag in ipairs(result) do
		set[tag] = true
	end
	expect.equality(set["project"], true)
	expect.equality(set["urgent"], true)
	expect.equality(set["my-tag"], true)
	expect.equality(set["under_score"], true)
	expect.equality(set["final"], true)
end

inline["does not fully track code block state"] = function()
	-- NOTE: get_inline_tags() only skips ``` delimiter lines, not content inside
	-- code blocks. read_file_metadata() handles this correctly with in_code_block
	-- tracking. This test documents the current behavior.
	local result = tags.get_inline_tags(fixtures .. "/inline_tags.md")
	local set = {}
	for _, tag in ipairs(result) do
		set[tag] = true
	end
	-- Tags on ``` lines are skipped, but tags on lines inside code blocks are NOT
	expect.equality(set["code-tag"], true)
end

inline["returns empty for file without tags"] = function()
	local result = tags.get_inline_tags(fixtures .. "/basic.md")
	expect.equality(#result, 0)
end

inline["returns empty for empty file"] = function()
	local result = tags.get_inline_tags(fixtures .. "/empty.md")
	expect.equality(#result, 0)
end

--------------------------------------------------------------------------------
-- read_file_metadata
--------------------------------------------------------------------------------

local meta = new_set()
T["read_file_metadata"] = meta

meta["extracts title from H1"] = function()
	local result = tags.read_file_metadata(fixtures .. "/headings.md")
	expect.equality(result.title, "Main Title")
end

meta["extracts frontmatter tags and title"] = function()
	local result = tags.read_file_metadata(fixtures .. "/frontmatter_inline.md")
	expect.equality(result.title, "Inline Tags Test")
	table.sort(result.tags)
	expect.equality(result.tags, { "alpha", "beta", "gamma" })
end

meta["returns empty for empty file"] = function()
	local result = tags.read_file_metadata(fixtures .. "/empty.md")
	expect.equality(result.title, nil)
	expect.equality(#result.tags, 0)
end

meta["extracts inline tags from content"] = function()
	local result = tags.read_file_metadata(fixtures .. "/inline_tags.md")
	local set = {}
	for _, tag in ipairs(result.tags) do
		set[tag] = true
	end
	expect.equality(set["project"], true)
	expect.equality(set["urgent"], true)
end

return T

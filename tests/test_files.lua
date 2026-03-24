local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

local files = require("womwiki.files")

local fixtures = vim.fn.getcwd() .. "/tests/fixtures"

local T = new_set()

--------------------------------------------------------------------------------
-- get_file_headings
--------------------------------------------------------------------------------

local headings = new_set()
T["get_file_headings"] = headings

headings["extracts all heading levels"] = function()
	local result = files.get_file_headings(fixtures .. "/headings.md")
	expect.equality(#result >= 6, true)
end

headings["captures heading text"] = function()
	local result = files.get_file_headings(fixtures .. "/headings.md")
	expect.equality(result[1].text, "Main Title")
	expect.equality(result[2].text, "Getting Started")
	expect.equality(result[3].text, "Installation Steps")
end

headings["captures correct heading levels"] = function()
	local result = files.get_file_headings(fixtures .. "/headings.md")
	expect.equality(result[1].level, 1)
	expect.equality(result[2].level, 2)
	expect.equality(result[3].level, 3)
	expect.equality(result[5].level, 4)
end

headings["generates slug with spaces as hyphens"] = function()
	local result = files.get_file_headings(fixtures .. "/headings.md")
	expect.equality(result[2].slug, "getting-started")
	expect.equality(result[3].slug, "installation-steps")
end

headings["strips punctuation from slug"] = function()
	local result = files.get_file_headings(fixtures .. "/headings.md")
	-- "API Reference (v2.0)" → "api-reference-v20"
	local api_heading = result[4]
	expect.equality(api_heading.text, "API Reference (v2.0)")
	-- Parentheses and dots stripped, spaces → hyphens
	expect.equality(api_heading.slug:find("[%(%)%.]"), nil)
end

headings["collapses consecutive hyphens in slug"] = function()
	local result = files.get_file_headings(fixtures .. "/headings.md")
	-- "Edge--Cases & Special \"Chars\"" → should not have consecutive hyphens
	local edge = result[6]
	expect.equality(edge.slug:find("%-%-"), nil)
end

headings["returns empty for file without headings"] = function()
	local result = files.get_file_headings(fixtures .. "/basic.md")
	expect.equality(#result, 0)
end

headings["returns empty for empty file"] = function()
	local result = files.get_file_headings(fixtures .. "/empty.md")
	expect.equality(#result, 0)
end

headings["returns empty for nonexistent file"] = function()
	local result = files.get_file_headings(fixtures .. "/does_not_exist.md")
	expect.equality(#result, 0)
end

--------------------------------------------------------------------------------
-- _replace_link_references
--------------------------------------------------------------------------------

local rl = new_set()
T["_replace_link_references"] = rl

rl["replaces wikilink"] = function()
	local content = "See [[old-page]] for details."
	local result, count = files._replace_link_references(content, "old-page", "new-page")
	expect.equality(result, "See [[new-page]] for details.")
	expect.equality(count, 1)
end

rl["replaces wikilink with display text"] = function()
	local content = "See [[old-page|My Page]] for details."
	local result, count = files._replace_link_references(content, "old-page", "new-page")
	expect.equality(result, "See [[new-page|My Page]] for details.")
	expect.equality(count, 1)
end

rl["replaces markdown link with .md"] = function()
	local content = "See [My Page](old-page.md) for details."
	local result, count = files._replace_link_references(content, "old-page", "new-page")
	expect.equality(result, "See [My Page](new-page.md) for details.")
	expect.equality(count, 1)
end

rl["replaces markdown link without .md"] = function()
	local content = "See [My Page](old-page) for details."
	local result, count = files._replace_link_references(content, "old-page", "new-page")
	expect.equality(result, "See [My Page](new-page) for details.")
	expect.equality(count, 1)
end

rl["replaces multiple link types in same content"] = function()
	local content = "Links: [[old-page]], [[old-page|display]], [text](old-page.md), [text](old-page)"
	local result, count = files._replace_link_references(content, "old-page", "new-page")
	expect.equality(result, "Links: [[new-page]], [[new-page|display]], [text](new-page.md), [text](new-page)")
	expect.equality(count, 4)
end

rl["does not replace partial matches"] = function()
	local content = "See [[old-page-extra]] and [[old-pager]]."
	local result, count = files._replace_link_references(content, "old-page", "new-page")
	-- [[old-page-extra]] should NOT match (wikilink pattern requires ]])
	-- [[old-pager]] should NOT match (wikilink pattern requires ]])
	expect.equality(result, "See [[old-page-extra]] and [[old-pager]].")
	expect.equality(count, 0)
end

rl["handles subdirectory paths"] = function()
	local content = "See [[projects/roadmap]] and [link](projects/roadmap.md)."
	local result, count = files._replace_link_references(content, "projects/roadmap", "projects/plan")
	expect.equality(result, "See [[projects/plan]] and [link](projects/plan.md).")
	expect.equality(count, 2)
end

rl["returns zero count when no matches"] = function()
	local content = "No links here, just text."
	local result, count = files._replace_link_references(content, "old-page", "new-page")
	expect.equality(result, content)
	expect.equality(count, 0)
end

return T

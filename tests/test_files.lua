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

return T

local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

local files = require("womwiki.files")

local fixtures = vim.fn.getcwd() .. "/tests/fixtures"

local T = new_set()

--------------------------------------------------------------------------------
-- async completion cache
--------------------------------------------------------------------------------

local async_cache = new_set()
T["async completion cache"] = async_cache

async_cache["indexes paths without blocking the caller"] = function()
	local config = require("womwiki.config")
	local old_config = config.config
	local old_wikidir = config.wikidir
	local old_dailydir = config.dailydir
	local old_cache = files.cache
	local wiki_dir = vim.fn.tempname()

	vim.fn.mkdir(wiki_dir .. "/nested", "p")
	vim.fn.writefile({ "# Slow Disk" }, wiki_dir .. "/note.md")
	vim.fn.writefile({ "# Nested" }, wiki_dir .. "/nested/child.md")
	config.setup({ path = wiki_dir })
	files.cache = { files = {}, last_scan = 0, ttl = 300, loading = false, dirty_during_scan = false, initial_scan_complete = false, callbacks = {} }

	local cached, loading = files.get_cached_wiki_files()
	expect.equality(#cached, 0)
	expect.equality(loading, true)
	expect.equality(vim.wait(1000, function()
		return not files.cache.loading
	end, 10), true)
	expect.equality(#files.cache.files, 2)
	expect.equality(files.cache.initial_scan_complete, true)
	expect.equality(files.cache.files[1].path, "nested/child.md")
	expect.equality(files.cache.files[2].path, "note.md")

	files.cache = old_cache
	config.config = old_config
	config.wikidir = old_wikidir
	config.dailydir = old_dailydir
	vim.fn.delete(wiki_dir, "rf")
end

async_cache["rescans when invalidated during an active scan"] = function()
	local config = require("womwiki.config")
	local old_config = config.config
	local old_wikidir = config.wikidir
	local old_dailydir = config.dailydir
	local old_cache = files.cache
	local wiki_dir = vim.fn.tempname()

	vim.fn.mkdir(wiki_dir, "p")
	vim.fn.writefile({ "# First" }, wiki_dir .. "/first.md")
	config.setup({ path = wiki_dir })
	files.cache = { files = {}, last_scan = 0, ttl = 300, loading = false, dirty_during_scan = false, initial_scan_complete = false, callbacks = {} }

	files.get_cached_wiki_files()
	files.invalidate_cache()
	expect.equality(files.cache.dirty_during_scan, true)
	vim.fn.writefile({ "# Second" }, wiki_dir .. "/second.md")
	expect.equality(vim.wait(1000, function()
		return not files.cache.loading and files.cache.last_scan > 0
	end, 10), true)
	expect.equality(#files.cache.files, 2)

	files.cache = old_cache
	config.config = old_config
	config.wikidir = old_wikidir
	config.dailydir = old_dailydir
	vim.fn.delete(wiki_dir, "rf")
end

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

headings["captures 1-based heading line numbers"] = function()
	local result = files.get_file_headings(fixtures .. "/headings.md")
	expect.equality(result[1].line, 1) -- # Main Title
	expect.equality(result[2].line, 5) -- ## Getting Started
	expect.equality(result[3].line, 9) -- ### Installation Steps
	expect.equality(result[4].line, 13) -- ## API Reference (v2.0)
end

--------------------------------------------------------------------------------
-- slugify
--------------------------------------------------------------------------------

local slugify = new_set()
T["slugify"] = slugify

slugify["lowercases and converts spaces to hyphens"] = function()
	expect.equality(files.slugify("Getting Started"), "getting-started")
end

slugify["strips punctuation"] = function()
	expect.equality(files.slugify("API Reference (v2.0)"), "api-reference-v20")
end

slugify["collapses consecutive hyphens"] = function()
	expect.equality(files.slugify('Edge--Cases & Special "Chars"'):find("%-%-"), nil)
end

slugify["trims leading and trailing hyphens"] = function()
	expect.equality(files.slugify("- Trim Me -"), "trim-me")
end

--------------------------------------------------------------------------------
-- find_heading_line
--------------------------------------------------------------------------------

local find_heading = new_set()
T["find_heading_line"] = find_heading

find_heading["resolves exact slug match"] = function()
	expect.equality(files.find_heading_line(fixtures .. "/headings.md", "getting-started"), 5)
	expect.equality(files.find_heading_line(fixtures .. "/headings.md", "installation-steps"), 9)
end

find_heading["falls back to case-insensitive match"] = function()
	expect.equality(files.find_heading_line(fixtures .. "/headings.md", "Getting-Started"), 5)
end

find_heading["returns nil for no match"] = function()
	expect.equality(files.find_heading_line(fixtures .. "/headings.md", "nonexistent"), nil)
end

find_heading["returns nil for empty slug"] = function()
	expect.equality(files.find_heading_line(fixtures .. "/headings.md", ""), nil)
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

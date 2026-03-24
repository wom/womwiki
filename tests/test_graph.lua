local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

-- Setup config with wikilinks enabled
require("womwiki.config").setup({ path = "/tmp/test-wiki" })
local graph = require("womwiki.graph")

local fixtures = vim.fn.getcwd() .. "/tests/fixtures"

local T = new_set()

--------------------------------------------------------------------------------
-- _get_links_from_file
--------------------------------------------------------------------------------

local links = new_set()
T["_get_links_from_file"] = links

links["extracts markdown links"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_b.md")
	local set = {}
	for _, link in ipairs(result) do
		set[link] = true
	end
	-- [Page A](page-a.md) should strip .md
	expect.equality(set["page-a"], true)
	-- [Page C](page-c)
	expect.equality(set["page-c"], true)
end

links["extracts wikilinks"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_a.md")
	local set = {}
	for _, link in ipairs(result) do
		set[link] = true
	end
	-- [[page-c]]
	expect.equality(set["page-c"], true)
	-- [[page-b|display text]] should extract just page-b
	expect.equality(set["page-b"], true)
end

links["extracts both markdown and wikilinks from same file"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_a.md")
	-- Should have: page-b (markdown), page-c (wikilink), page-b (wikilink with display)
	expect.equality(#result >= 3, true)
end

links["skips URLs"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_a.md")
	for _, link in ipairs(result) do
		expect.equality(link:match("^https?://"), nil)
	end
end

links["skips URLs in orphan fixture"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_orphan.md")
	expect.equality(#result, 0)
end

links["returns empty for file with no links"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_nolinks.md")
	expect.equality(#result, 0)
end

links["returns empty for empty file"] = function()
	local result = graph._get_links_from_file(fixtures .. "/empty.md")
	expect.equality(#result, 0)
end

links["returns empty for nonexistent file"] = function()
	local result = graph._get_links_from_file(fixtures .. "/does_not_exist.md")
	expect.equality(#result, 0)
end

links["handles wikilink with spaces converted to dashes"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_wikilinks.md")
	local set = {}
	for _, link in ipairs(result) do
		set[link] = true
	end
	-- [[my page]] with spaces_to = "-" becomes my-page
	expect.equality(set["my-page"], true)
end

links["extracts pipe-separated wikilink target only"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_wikilinks.md")
	local set = {}
	for _, link in ipairs(result) do
		set[link] = true
	end
	-- [[target|display name]] should extract just "target"
	expect.equality(set["target"], true)
end

links["extracts multiple wikilinks from one line"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_wikilinks.md")
	local set = {}
	for _, link in ipairs(result) do
		set[link] = true
	end
	-- [[alpha]] and [[beta]] on same line
	expect.equality(set["alpha"], true)
	expect.equality(set["beta"], true)
end

links["strips .md extension from markdown links"] = function()
	local result = graph._get_links_from_file(fixtures .. "/graph_b.md")
	for _, link in ipairs(result) do
		expect.equality(link:match("%.md$"), nil)
	end
end

--------------------------------------------------------------------------------
-- _build_link_graph (integration with fixtures as mini wiki)
--------------------------------------------------------------------------------

local bg = new_set()
T["_build_link_graph"] = bg

-- Helper: set up a mini wiki directory with known fixture files
local function setup_mini_wiki()
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")

	-- Copy graph fixtures to temp wiki dir
	local fixture_files = { "graph_a.md", "graph_b.md", "graph_c.md", "graph_orphan.md" }
	for _, fname in ipairs(fixture_files) do
		local src = io.open(fixtures .. "/" .. fname, "r")
		if src then
			local content = src:read("*a")
			src:close()
			-- Rename to match link targets (remove graph_ prefix)
			local target_name = fname:gsub("^graph_", "")
			-- Special case: a.md, b.md, c.md should be page-a.md etc.
			if target_name == "a.md" then
				target_name = "page-a.md"
			elseif target_name == "b.md" then
				target_name = "page-b.md"
			elseif target_name == "c.md" then
				target_name = "page-c.md"
			end
			local dst = io.open(tmpdir .. "/" .. target_name, "w")
			if dst then
				dst:write(content)
				dst:close()
			end
		end
	end

	-- Also create a daily/ subdir to test exclusion
	vim.fn.mkdir(tmpdir .. "/daily", "p")
	local daily_file = io.open(tmpdir .. "/daily/2024-01-01.md", "w")
	if daily_file then
		daily_file:write("# Daily\n[[page-a]]\n")
		daily_file:close()
	end

	return tmpdir
end

local function cleanup_mini_wiki(tmpdir)
	vim.fn.delete(tmpdir, "rf")
end

bg["builds graph with correct adjacency"] = function()
	local tmpdir = setup_mini_wiki()
	-- Point config at our temp wiki
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local result = graph._build_link_graph()

	-- page-a links to page-b (markdown) and page-c (wikilink) and page-b (wikilink)
	expect.no_equality(result["page-a"], nil)
	local a_targets = {}
	for _, t in ipairs(result["page-a"].links_to) do
		a_targets[t] = true
	end
	expect.equality(a_targets["page-b"], true)
	expect.equality(a_targets["page-c"], true)

	-- page-b should have backlinks from page-a
	expect.no_equality(result["page-b"], nil)
	local b_from = {}
	for _, f in ipairs(result["page-b"].linked_from) do
		b_from[f] = true
	end
	expect.equality(b_from["page-a"], true)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

bg["identifies orphan files"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local result = graph._build_link_graph()

	-- orphan.md has no links and no incoming links
	expect.no_equality(result["orphan"], nil)
	expect.equality(#result["orphan"].links_to, 0)
	expect.equality(#result["orphan"].linked_from, 0)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

bg["excludes daily directory"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local result = graph._build_link_graph()

	-- daily/2024-01-01 should NOT be in the graph
	expect.equality(result["2024-01-01"], nil)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

bg["handles empty wiki directory"] = function()
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local result = graph._build_link_graph()

	-- Empty dir = empty graph
	local count = 0
	for _ in pairs(result) do
		count = count + 1
	end
	expect.equality(count, 0)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

bg["only includes links to existing files"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local result = graph._build_link_graph()

	-- page-a links to page-c which exists, but if page-c links to page-a
	-- Links should only appear if target file actually exists
	for _, data in pairs(result) do
		for _, target in ipairs(data.links_to) do
			expect.no_equality(result[target], nil)
		end
	end

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

bg["keys subdirectory files by relative path"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	-- Create a subdirectory with a file
	vim.fn.mkdir(tmpdir .. "/projects", "p")
	local f = io.open(tmpdir .. "/projects/roadmap.md", "w")
	if f then
		f:write("# Roadmap\n[[page-a]]\n")
		f:close()
	end

	local result = graph._build_link_graph()

	-- Subdirectory file should be keyed by relative path
	expect.no_equality(result["projects/roadmap"], nil)
	-- Should NOT be keyed by basename alone
	expect.equality(result["roadmap"], nil)

	-- Its link to page-a should be tracked
	local targets = {}
	for _, t in ipairs(result["projects/roadmap"].links_to) do
		targets[t] = true
	end
	expect.equality(targets["page-a"], true)

	-- page-a should have backlink from projects/roadmap
	local a_from = {}
	for _, from in ipairs(result["page-a"].linked_from) do
		a_from[from] = true
	end
	expect.equality(a_from["projects/roadmap"], true)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

bg["excludes custom daily directory"] = function()
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/journal"

	-- Create files in custom daily dir and a regular file
	vim.fn.mkdir(tmpdir .. "/journal", "p")
	local f1 = io.open(tmpdir .. "/journal/2024-01-01.md", "w")
	if f1 then
		f1:write("# Daily\n")
		f1:close()
	end
	local f2 = io.open(tmpdir .. "/note.md", "w")
	if f2 then
		f2:write("# Note\n")
		f2:close()
	end

	local result = graph._build_link_graph()

	-- Journal file should be excluded
	expect.equality(result["2024-01-01"], nil)
	expect.equality(result["journal/2024-01-01"], nil)
	-- Regular file should be included
	expect.no_equality(result["note"], nil)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	vim.fn.delete(tmpdir, "rf")
end

--------------------------------------------------------------------------------
-- _is_daily_note
--------------------------------------------------------------------------------

local dn = new_set()
T["_is_daily_note"] = dn

dn["matches daily note path"] = function()
	local config = require("womwiki.config")
	local orig_dailydir = config.dailydir
	config.dailydir = "/tmp/wiki/daily"

	expect.equality(graph._is_daily_note("/tmp/wiki/daily/2024-01-15.md"), true)
	expect.equality(graph._is_daily_note("/tmp/wiki/daily/2024-12-31.md"), true)

	config.dailydir = orig_dailydir
end

dn["rejects non-daily paths"] = function()
	local config = require("womwiki.config")
	local orig_dailydir = config.dailydir
	config.dailydir = "/tmp/wiki/daily"

	expect.equality(graph._is_daily_note("/tmp/wiki/page.md"), false)
	expect.equality(graph._is_daily_note("/tmp/wiki/notes/page.md"), false)

	config.dailydir = orig_dailydir
end

dn["handles nil dailydir"] = function()
	local config = require("womwiki.config")
	local orig_dailydir = config.dailydir
	config.dailydir = nil

	expect.equality(graph._is_daily_note("/tmp/wiki/daily/2024-01-15.md"), false)

	config.dailydir = orig_dailydir
end

dn["does not match partial directory names"] = function()
	local config = require("womwiki.config")
	local orig_dailydir = config.dailydir
	config.dailydir = "/tmp/wiki/daily"

	-- "daily-notes" should NOT match "daily"
	expect.equality(graph._is_daily_note("/tmp/wiki/daily-notes/file.md"), false)

	config.dailydir = orig_dailydir
end

--------------------------------------------------------------------------------
-- _get_all_wiki_files
--------------------------------------------------------------------------------

local wf = new_set()
T["_get_all_wiki_files"] = wf

wf["includes subdirectory files with relative paths"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	-- Create a subdirectory with a file
	vim.fn.mkdir(tmpdir .. "/projects", "p")
	local f = io.open(tmpdir .. "/projects/roadmap.md", "w")
	if f then
		f:write("# Roadmap\n")
		f:close()
	end

	local files = graph._get_all_wiki_files()

	local found = false
	for _, file in ipairs(files) do
		if file.relative == "projects/roadmap.md" then
			found = true
			expect.equality(file.name, "roadmap")
			expect.equality(file.path, tmpdir .. "/projects/roadmap.md")
		end
	end
	expect.equality(found, true)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

wf["excludes daily directory files"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local files = graph._get_all_wiki_files()

	for _, file in ipairs(files) do
		expect.equality(vim.startswith(file.relative, "daily/"), false)
	end

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

--------------------------------------------------------------------------------
-- get_link_graph (caching layer)
--------------------------------------------------------------------------------

local cg = new_set()
T["get_link_graph"] = cg

cg["cache structure exists"] = function()
	expect.no_equality(graph.cache, nil)
	expect.equality(type(graph.cache.ttl), "number")
	expect.equality(type(graph.cache.last_scan), "number")
	expect.equality(type(graph.cache.rebuilding), "boolean")
end

cg["returns same reference on consecutive calls"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	-- Reset cache to force fresh build
	graph.cache.graph = nil
	graph.cache.last_scan = 0
	graph.cache.rebuilding = false

	local first = graph.get_link_graph()
	local second = graph.get_link_graph()
	expect.equality(rawequal(first, second), true)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

cg["invalidate forces rebuild"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	-- Reset cache to force fresh build
	graph.cache.graph = nil
	graph.cache.last_scan = 0
	graph.cache.rebuilding = false

	local first = graph.get_link_graph()
	graph.invalidate_cache()
	-- After invalidation, cache.graph is still set so async path would be taken.
	-- Force synchronous rebuild by clearing cache.graph too.
	graph.cache.graph = nil
	local second = graph.get_link_graph()
	expect.equality(rawequal(first, second), false)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

--------------------------------------------------------------------------------
-- broken links (from build_link_graph second return value)
--------------------------------------------------------------------------------

local bl = new_set()
T["broken_links"] = bl

bl["returns broken links for non-existent targets"] = function()
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	-- Create a file that links to non-existent targets
	local f = io.open(tmpdir .. "/source.md", "w")
	if f then
		f:write("# Source\n[[missing-page]]\n[link](also-missing.md)\n")
		f:close()
	end

	local _, broken = graph._build_link_graph()

	expect.no_equality(broken["source"], nil)
	local targets = {}
	for _, t in ipairs(broken["source"]) do
		targets[t] = true
	end
	expect.equality(targets["missing-page"], true)
	expect.equality(targets["also-missing"], true)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	vim.fn.delete(tmpdir, "rf")
end

bl["valid links are not in broken_links"] = function()
	local tmpdir = setup_mini_wiki()
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local _, broken = graph._build_link_graph()

	-- All links in the mini wiki fixtures resolve to existing files
	local total_broken = 0
	for _, targets in pairs(broken) do
		total_broken = total_broken + #targets
	end
	expect.equality(total_broken, 0)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	cleanup_mini_wiki(tmpdir)
end

bl["empty wiki has no broken links"] = function()
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local _, broken = graph._build_link_graph()

	local count = 0
	for _ in pairs(broken) do
		count = count + 1
	end
	expect.equality(count, 0)

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	vim.fn.delete(tmpdir, "rf")
end

bl["mixed valid and broken links"] = function()
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	-- Create two files, one links to the other + a broken link
	local f1 = io.open(tmpdir .. "/real.md", "w")
	if f1 then
		f1:write("# Real\n")
		f1:close()
	end
	local f2 = io.open(tmpdir .. "/linker.md", "w")
	if f2 then
		f2:write("# Linker\n[[real]]\n[[ghost]]\n")
		f2:close()
	end

	local result, broken = graph._build_link_graph()

	-- Valid link should be in graph
	local linker_targets = {}
	for _, t in ipairs(result["linker"].links_to) do
		linker_targets[t] = true
	end
	expect.equality(linker_targets["real"], true)

	-- Broken link should be in broken_links
	expect.no_equality(broken["linker"], nil)
	expect.equality(broken["linker"][1], "ghost")

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	vim.fn.delete(tmpdir, "rf")
end

bl["get_broken_links returns cached broken links"] = function()
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local config = require("womwiki.config")
	local orig_wikidir = config.wikidir
	local orig_dailydir = config.dailydir
	config.wikidir = tmpdir
	config.dailydir = tmpdir .. "/daily"

	local f = io.open(tmpdir .. "/test.md", "w")
	if f then
		f:write("# Test\n[[nonexistent]]\n")
		f:close()
	end

	-- Reset cache
	graph.cache.graph = nil
	graph.cache.broken_links = nil
	graph.cache.last_scan = 0
	graph.cache.rebuilding = false

	local broken = graph.get_broken_links()
	expect.no_equality(broken["test"], nil)
	expect.equality(broken["test"][1], "nonexistent")

	config.wikidir = orig_wikidir
	config.dailydir = orig_dailydir
	vim.fn.delete(tmpdir, "rf")
end

return T

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

return T

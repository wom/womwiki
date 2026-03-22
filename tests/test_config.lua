local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

local config = require("womwiki.config")

local T = new_set()

--------------------------------------------------------------------------------
-- setup / config merging
--------------------------------------------------------------------------------

local setup = new_set({
	hooks = {
		pre_case = function()
			-- Reset config to defaults before each test
			config.config = {
				path = os.getenv("HOME") .. "/src/wiki",
				picker = nil,
				inbox = {
					file = "inbox.md",
					format = "- [ ] {{ datetime }} - {{ text }}",
					datetime_format = "%Y-%m-%d %H:%M",
				},
				completion = {
					enabled = true,
					include_headings = true,
					max_results = 50,
					cache_ttl = 300,
				},
				wikilinks = {
					enabled = true,
					spaces_to = "-",
					confirm_create = true,
				},
				tags = {
					enabled = true,
					inline_pattern = "#([%w_-]+)",
					use_frontmatter = true,
				},
				default_link_style = "markdown",
			}
		end,
	},
})
T["setup"] = setup

setup["nil opts preserves defaults"] = function()
	config.setup(nil)
	expect.equality(config.config.path, os.getenv("HOME") .. "/src/wiki")
	expect.equality(config.config.completion.enabled, true)
	expect.equality(config.config.default_link_style, "markdown")
end

setup["overrides top-level field"] = function()
	config.setup({ path = "/tmp/my-wiki" })
	expect.equality(config.config.path, "/tmp/my-wiki")
end

setup["overrides nested field preserving siblings"] = function()
	config.setup({ completion = { max_results = 100 } })
	expect.equality(config.config.completion.max_results, 100)
	-- Sibling fields should be preserved
	expect.equality(config.config.completion.enabled, true)
	expect.equality(config.config.completion.include_headings, true)
	expect.equality(config.config.completion.cache_ttl, 300)
end

setup["can override multiple sections"] = function()
	config.setup({
		path = "/tmp/wiki2",
		completion = { cache_ttl = 60 },
		tags = { enabled = false },
	})
	expect.equality(config.config.path, "/tmp/wiki2")
	expect.equality(config.config.completion.cache_ttl, 60)
	expect.equality(config.config.tags.enabled, false)
	-- Unaffected sections preserved
	expect.equality(config.config.wikilinks.enabled, true)
end

setup["resolves paths after setup"] = function()
	config.setup({ path = "/tmp" })
	expect.no_equality(config.wikidir, nil)
	expect.no_equality(config.dailydir, nil)
	-- dailydir should end with /daily
	expect.no_equality(config.dailydir:find("/daily$"), nil)
end

setup["all defaults present with empty opts"] = function()
	config.setup({})
	expect.no_equality(config.config.inbox, nil)
	expect.no_equality(config.config.completion, nil)
	expect.no_equality(config.config.wikilinks, nil)
	expect.no_equality(config.config.tags, nil)
	expect.equality(type(config.config.inbox.file), "string")
	expect.equality(type(config.config.completion.max_results), "number")
	expect.equality(type(config.config.wikilinks.spaces_to), "string")
	expect.equality(type(config.config.tags.inline_pattern), "string")
end

return T

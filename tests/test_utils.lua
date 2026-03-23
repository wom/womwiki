local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

-- Setup config (no picker installed in headless)
require("womwiki.config").setup({ path = "/tmp/test-wiki" })
local utils = require("womwiki.utils")

local T = new_set()

--------------------------------------------------------------------------------
-- ensure_md_extension
--------------------------------------------------------------------------------

local md = new_set()
T["ensure_md_extension"] = md

md["adds .md to plain filename"] = function()
	expect.equality(utils.ensure_md_extension("myfile"), "myfile.md")
end

md["preserves existing .md extension"] = function()
	expect.equality(utils.ensure_md_extension("myfile.md"), "myfile.md")
end

md["adds .md to filename with other extension"] = function()
	expect.equality(utils.ensure_md_extension("file.txt"), "file.txt.md")
end

md["adds .md to filename with dots"] = function()
	expect.equality(utils.ensure_md_extension("a.b.c"), "a.b.c.md")
end

md["adds .md to empty string"] = function()
	expect.equality(utils.ensure_md_extension(""), ".md")
end

md["adds .md to filename with path separators"] = function()
	expect.equality(utils.ensure_md_extension("dir/file"), "dir/file.md")
end

md["preserves .md in path with directory"] = function()
	expect.equality(utils.ensure_md_extension("dir/file.md"), "dir/file.md")
end

md["handles filename that is just .md"] = function()
	expect.equality(utils.ensure_md_extension(".md"), ".md")
end

md["adds .md to filename with spaces"] = function()
	expect.equality(utils.ensure_md_extension("my file"), "my file.md")
end

md["adds .md to hyphenated filename"] = function()
	expect.equality(utils.ensure_md_extension("my-note"), "my-note.md")
end

--------------------------------------------------------------------------------
-- get_picker (headless — no picker plugins available)
--------------------------------------------------------------------------------

local picker = new_set()
T["get_picker"] = picker

picker["returns nil when no picker installed"] = function()
	-- In headless test env, mini.pick IS available (from mini.nvim).
	-- Test that explicitly configured nonexistent picker returns nil.
	local config = require("womwiki.config")
	local orig_picker = config.config.picker
	config.config.picker = "snacks"

	local picker_type, picker_mod = utils.get_picker()
	-- snacks is not installed, so should fail
	expect.equality(picker_type, nil)
	expect.equality(picker_mod, nil)

	config.config.picker = orig_picker
end

picker["returns nil for unconfigured specific picker"] = function()
	local config = require("womwiki.config")
	local orig_picker = config.config.picker
	config.config.picker = "telescope"

	local picker_type, picker_mod = utils.get_picker()
	expect.equality(picker_type, nil)
	expect.equality(picker_mod, nil)

	config.config.picker = orig_picker
end

picker["auto-detects mini.pick in test environment"] = function()
	-- mini.nvim is in runtimepath for tests, so mini.pick should be found
	local config = require("womwiki.config")
	local orig_picker = config.config.picker
	config.config.picker = nil

	local picker_type, _ = utils.get_picker()
	-- Should auto-detect mini.pick (from test bootstrap)
	expect.equality(picker_type, "mini")

	config.config.picker = orig_picker
end

return T

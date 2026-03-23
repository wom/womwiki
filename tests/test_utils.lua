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

--------------------------------------------------------------------------------
-- File I/O helpers
--------------------------------------------------------------------------------

local eq = expect.equality
local neq = expect.no_equality

local file_io = new_set()
T["file_io"] = file_io

-- read_file

file_io["read_file reads file contents"] = function()
	local tmp = vim.fn.tempname()
	local f = io.open(tmp, "w")
	f:write("hello world")
	f:close()
	local content, err = utils.read_file(tmp)
	eq(content, "hello world")
	eq(err, nil)
	os.remove(tmp)
end

file_io["read_file returns nil for missing file"] = function()
	local content, err = utils.read_file("/tmp/nonexistent_womwiki_test_file")
	eq(content, nil)
	neq(err, nil)
end

-- read_lines

file_io["read_lines reads lines into array"] = function()
	local tmp = vim.fn.tempname()
	local f = io.open(tmp, "w")
	f:write("line1\nline2\nline3\n")
	f:close()
	local lines, err = utils.read_lines(tmp)
	eq(err, nil)
	eq(#lines, 3)
	eq(lines[1], "line1")
	eq(lines[2], "line2")
	eq(lines[3], "line3")
	os.remove(tmp)
end

file_io["read_lines returns nil for missing file"] = function()
	local lines, err = utils.read_lines("/tmp/nonexistent_womwiki_test_file")
	eq(lines, nil)
	neq(err, nil)
end

file_io["read_lines returns empty table for empty file"] = function()
	local tmp = vim.fn.tempname()
	local f = io.open(tmp, "w")
	f:close()
	local lines, err = utils.read_lines(tmp)
	eq(err, nil)
	eq(#lines, 0)
	os.remove(tmp)
end

-- write_file

file_io["write_file writes content"] = function()
	local tmp = vim.fn.tempname()
	local ok, err = utils.write_file(tmp, "test content")
	eq(ok, true)
	eq(err, nil)
	local f = io.open(tmp, "r")
	local content = f:read("*a")
	f:close()
	eq(content, "test content")
	os.remove(tmp)
end

file_io["write_file overwrites existing content"] = function()
	local tmp = vim.fn.tempname()
	utils.write_file(tmp, "old")
	utils.write_file(tmp, "new")
	local content = utils.read_file(tmp)
	eq(content, "new")
	os.remove(tmp)
end

file_io["write_file returns false for invalid path"] = function()
	local ok, err = utils.write_file("/nonexistent_dir/file.txt", "data")
	eq(ok, false)
	neq(err, nil)
end

-- append_file

file_io["append_file appends to existing file"] = function()
	local tmp = vim.fn.tempname()
	utils.write_file(tmp, "first\n")
	local ok, err = utils.append_file(tmp, "second\n")
	eq(ok, true)
	eq(err, nil)
	local content = utils.read_file(tmp)
	eq(content, "first\nsecond\n")
	os.remove(tmp)
end

file_io["append_file creates file if missing"] = function()
	local tmp = vim.fn.tempname()
	local ok, err = utils.append_file(tmp, "appended")
	eq(ok, true)
	eq(err, nil)
	local content = utils.read_file(tmp)
	eq(content, "appended")
	os.remove(tmp)
end

file_io["append_file returns false for invalid path"] = function()
	local ok, err = utils.append_file("/nonexistent_dir/file.txt", "data")
	eq(ok, false)
	neq(err, nil)
end

return T

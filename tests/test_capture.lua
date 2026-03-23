local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

-- Setup config so capture module can load
require("womwiki.config").setup({ path = "/tmp/test-wiki" })
local capture = require("womwiki.capture")

local T = new_set()

-- Helper to read file contents
local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

--------------------------------------------------------------------------------
-- _format_entry
--------------------------------------------------------------------------------

local fmt = new_set()
T["_format_entry"] = fmt

fmt["formats entry with default template"] = function()
	local inbox_config = {
		format = "- [ ] {{ datetime }} - {{ text }}",
		datetime_format = "%Y-%m-%d %H:%M",
	}
	local result = capture._format_entry("hello world", inbox_config)
	-- Should contain the text
	expect.no_equality(result:find("hello world"), nil)
	-- Should start with checkbox
	expect.no_equality(result:find("^- %["), nil)
	-- Should contain a date-like pattern
	expect.no_equality(result:find("%d%d%d%d%-%d%d%-%d%d"), nil)
end

fmt["formats entry with custom template"] = function()
	local inbox_config = {
		format = "* {{ text }} ({{ datetime }})",
		datetime_format = "%H:%M",
	}
	local result = capture._format_entry("test note", inbox_config)
	expect.no_equality(result:find("test note"), nil)
	expect.no_equality(result:find("^%*"), nil)
end

fmt["handles special regex characters in text"] = function()
	local inbox_config = {
		format = "- {{ text }}",
		datetime_format = "%Y-%m-%d",
	}
	-- % is special in gsub patterns — text should still be inserted correctly
	local result = capture._format_entry("100% done", inbox_config)
	expect.no_equality(result:find("100"), nil)
	expect.no_equality(result:find("done"), nil)
end

fmt["preserves template structure around text"] = function()
	local inbox_config = {
		format = "PREFIX {{ datetime }} MIDDLE {{ text }} SUFFIX",
		datetime_format = "%Y",
	}
	local result = capture._format_entry("content", inbox_config)
	expect.no_equality(result:find("PREFIX"), nil)
	expect.no_equality(result:find("MIDDLE"), nil)
	expect.no_equality(result:find("SUFFIX"), nil)
	expect.no_equality(result:find("content"), nil)
end

--------------------------------------------------------------------------------
-- _append_to_inbox
--------------------------------------------------------------------------------

local append = new_set()
T["_append_to_inbox"] = append

append["creates file with header when file does not exist"] = function()
	local tmpfile = vim.fn.tempname() .. ".md"
	local ok = capture._append_to_inbox("- test entry", tmpfile)
	expect.equality(ok, true)

	local content = read_file(tmpfile)
	expect.no_equality(content, nil)
	-- Should have inbox header
	expect.no_equality(content:find("# Inbox"), nil)
	expect.no_equality(content:find("Quick captures"), nil)
	-- Should have our entry
	expect.no_equality(content:find("test entry"), nil)
	os.remove(tmpfile)
end

append["appends to existing file"] = function()
	local tmpfile = vim.fn.tempname() .. ".md"
	-- Create file with some content
	local file = io.open(tmpfile, "w")
	file:write("# Existing Content\n\nSome stuff.\n")
	file:close()

	local ok = capture._append_to_inbox("- new entry", tmpfile)
	expect.equality(ok, true)

	local content = read_file(tmpfile)
	-- Should preserve existing content
	expect.no_equality(content:find("Existing Content"), nil)
	-- Should have new entry
	expect.no_equality(content:find("new entry"), nil)
	os.remove(tmpfile)
end

append["appends multiple entries"] = function()
	local tmpfile = vim.fn.tempname() .. ".md"

	capture._append_to_inbox("- entry one", tmpfile)
	capture._append_to_inbox("- entry two", tmpfile)
	capture._append_to_inbox("- entry three", tmpfile)

	local content = read_file(tmpfile)
	expect.no_equality(content:find("entry one"), nil)
	expect.no_equality(content:find("entry two"), nil)
	expect.no_equality(content:find("entry three"), nil)
	os.remove(tmpfile)
end

append["returns false for unwritable path"] = function()
	local ok, err = capture._append_to_inbox("- test", "/nonexistent/deep/path/file.md")
	expect.equality(ok, false)
	expect.no_equality(err, nil)
end

append["entry ends with newline in file"] = function()
	local tmpfile = vim.fn.tempname() .. ".md"
	-- Seed with existing file so header doesn't interfere
	local file = io.open(tmpfile, "w")
	file:write("# Inbox\n\n")
	file:close()

	capture._append_to_inbox("- test entry", tmpfile)
	local content = read_file(tmpfile)
	-- Entry should end with newline
	expect.no_equality(content:find("test entry\n"), nil)
	os.remove(tmpfile)
end

return T

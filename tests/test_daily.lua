local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

require("womwiki.config").setup({ path = "/tmp/test-wiki" })
local daily = require("womwiki.daily")

local fixtures = vim.fn.getcwd() .. "/tests/fixtures"

local T = new_set()

--------------------------------------------------------------------------------
-- extract_incomplete_todos
--------------------------------------------------------------------------------

local extract = new_set()
T["extract_incomplete_todos"] = extract

extract["extracts unchecked todos"] = function()
	local result = daily.extract_incomplete_todos(fixtures .. "/daily_todos.md")
	local has_write_tests = false
	local has_update_docs = false
	for _, line in ipairs(result) do
		if line:match("Write unit tests") then
			has_write_tests = true
		end
		if line:match("Update documentation") then
			has_update_docs = true
		end
	end
	expect.equality(has_write_tests, true)
	expect.equality(has_update_docs, true)
end

extract["extracts in-progress todos"] = function()
	local result = daily.extract_incomplete_todos(fixtures .. "/daily_todos.md")
	local has_review = false
	for _, line in ipairs(result) do
		if line:match("Review pull request") then
			has_review = true
		end
	end
	expect.equality(has_review, true)
end

extract["skips completed todos"] = function()
	local result = daily.extract_incomplete_todos(fixtures .. "/daily_todos.md")
	for _, line in ipairs(result) do
		expect.equality(line:match("Fix login bug"), nil)
	end
end

extract["skips forwarded todos"] = function()
	local result = daily.extract_incomplete_todos(fixtures .. "/daily_todos.md")
	for _, line in ipairs(result) do
		expect.equality(line:match("Deploy to staging"), nil)
	end
end

extract["extracts nested incomplete todos"] = function()
	local result = daily.extract_incomplete_todos(fixtures .. "/daily_todos.md")
	local has_nested = false
	for _, line in ipairs(result) do
		if line:match("Nested incomplete todo") then
			has_nested = true
		end
	end
	expect.equality(has_nested, true)
end

extract["returns empty for empty file"] = function()
	local result = daily.extract_incomplete_todos(fixtures .. "/empty.md")
	expect.equality(#result, 0)
end

extract["returns empty for nonexistent file"] = function()
	local result = daily.extract_incomplete_todos(fixtures .. "/does_not_exist.md")
	expect.equality(#result, 0)
end

--------------------------------------------------------------------------------
-- mark_todos_forwarded
--------------------------------------------------------------------------------

local mark = new_set()
T["mark_todos_forwarded"] = mark

-- Helper: copy fixture to temp file for write tests
local function copy_to_temp(src)
	local tmpfile = vim.fn.tempname() .. ".md"
	local f_in = io.open(src, "r")
	if not f_in then
		return nil
	end
	local content = f_in:read("*a")
	f_in:close()
	local f_out = io.open(tmpfile, "w")
	if not f_out then
		return nil
	end
	f_out:write(content)
	f_out:close()
	return tmpfile
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

mark["converts unchecked to forwarded"] = function()
	local tmp = copy_to_temp(fixtures .. "/daily_todos.md")
	local todos = { "- [ ] Write unit tests" }
	local ok = daily.mark_todos_forwarded(tmp, todos)
	expect.equality(ok, true)

	local content = read_file(tmp)
	expect.no_equality(content:find("%[>%] Write unit tests"), nil)
	os.remove(tmp)
end

mark["converts in-progress to forwarded"] = function()
	local tmp = copy_to_temp(fixtures .. "/daily_todos.md")
	local todos = { "- [-] Review pull request" }
	local ok = daily.mark_todos_forwarded(tmp, todos)
	expect.equality(ok, true)

	local content = read_file(tmp)
	expect.no_equality(content:find("%[>%] Review pull request"), nil)
	os.remove(tmp)
end

mark["preserves completed todos"] = function()
	local tmp = copy_to_temp(fixtures .. "/daily_todos.md")
	local todos = { "- [ ] Write unit tests" }
	daily.mark_todos_forwarded(tmp, todos)

	local content = read_file(tmp)
	expect.no_equality(content:find("%[x%] Fix login bug"), nil)
	os.remove(tmp)
end

mark["returns false for nonexistent file"] = function()
	local ok = daily.mark_todos_forwarded("/tmp/does_not_exist_" .. os.time() .. ".md", { "- [ ] test" })
	expect.equality(ok, false)
end

--------------------------------------------------------------------------------
-- update_file_nav_line
--------------------------------------------------------------------------------

local nav = new_set()
T["update_file_nav_line"] = nav

-- Helper: copy fixture to temp with a daily-note filename (YYYY-MM-DD.md)
local function copy_to_daily_temp(src)
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local tmpfile = tmpdir .. "/2026-03-20.md"
	local f_in = io.open(src, "r")
	if not f_in then
		return nil
	end
	local content = f_in:read("*a")
	f_in:close()
	local f_out = io.open(tmpfile, "w")
	if not f_out then
		return nil
	end
	f_out:write(content)
	f_out:close()
	return tmpfile
end

nav["replaces old format with new"] = function()
	local tmp = copy_to_daily_temp(fixtures .. "/daily_old_nav.md")
	local changed = daily.update_file_nav_line(tmp)
	expect.equality(changed, true)

	local content = read_file(tmp)
	-- First line should now be new wikilink format
	local first_line = content:match("^([^\n]+)")
	expect.equality(first_line, "<!-- [[« Prev]] · [[Next »]] -->")
	-- Date heading should still be present
	expect.no_equality(content:find("# 2026%-03%-20"), nil)
	os.remove(tmp)
end

nav["leaves new format unchanged"] = function()
	local tmp = copy_to_daily_temp(fixtures .. "/daily_new_nav.md")
	local original = read_file(tmp)
	local changed = daily.update_file_nav_line(tmp)
	expect.equality(changed, false)

	local after = read_file(tmp)
	expect.equality(original, after)
	os.remove(tmp)
end

nav["prepends nav line when missing"] = function()
	local tmp = copy_to_daily_temp(fixtures .. "/daily_no_nav.md")
	local changed = daily.update_file_nav_line(tmp)
	expect.equality(changed, true)

	local content = read_file(tmp)
	local first_line = content:match("^([^\n]+)")
	expect.equality(first_line, "<!-- [[« Prev]] · [[Next »]] -->")
	-- Date heading should be on line 2
	local second_line = content:match("^[^\n]+\n([^\n]+)")
	expect.equality(second_line, "# 2026-03-20")
	os.remove(tmp)
end

nav["returns false for nonexistent file"] = function()
	local changed = daily.update_file_nav_line("/tmp/does_not_exist_" .. os.time() .. ".md")
	expect.equality(changed, false)
end

nav["returns false for empty file"] = function()
	local tmp = copy_to_daily_temp(fixtures .. "/empty.md")
	local changed = daily.update_file_nav_line(tmp)
	expect.equality(changed, false)
	os.remove(tmp)
end

nav["skips file with unrecognized first line"] = function()
	-- A file whose first line is neither nav format nor date heading
	local tmpdir = vim.fn.tempname()
	vim.fn.mkdir(tmpdir, "p")
	local tmpfile = tmpdir .. "/2026-03-20.md"
	local f = io.open(tmpfile, "w")
	f:write("---\ntitle: Some note\n---\n# 2026-03-20\n")
	f:close()

	local changed = daily.update_file_nav_line(tmpfile)
	expect.equality(changed, false)

	-- Content should be unchanged
	local content = read_file(tmpfile)
	expect.equality(content:match("^([^\n]+)"), "---")
	os.remove(tmpfile)
end

return T

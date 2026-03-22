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

return T

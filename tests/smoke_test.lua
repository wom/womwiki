-- Smoke test: verify plugin loads without errors
local ok, womwiki = pcall(require, "womwiki")

if not ok then
	print("ERROR: Failed to load womwiki module")
	print(womwiki)
	vim.cmd("cquit 1")
end

-- Test setup function exists
if type(womwiki.setup) ~= "function" then
	print("ERROR: womwiki.setup is not a function")
	vim.cmd("cquit 1")
end

-- Try to call setup with minimal config
local setup_ok, err = pcall(function()
	womwiki.setup({ path = "/tmp/test-wiki" })
end)

if not setup_ok then
	print("ERROR: Failed to run womwiki.setup()")
	print(err)
	vim.cmd("cquit 1")
end

print("SUCCESS: womwiki plugin loaded and initialized")


local health = vim.health
local config = require("womwiki.config")

local M = {}

--- Check Neovim version meets minimum requirements
local function check_neovim_version()
	health.start("Neovim version")
	local v = vim.version()
	local version_str = string.format("%d.%d.%d", v.major, v.minor, v.patch)
	if v.major > 0 or v.minor >= 10 then
		health.ok("Neovim " .. version_str)
	elseif v.minor == 9 then
		health.warn("Neovim " .. version_str .. " (0.10+ recommended for full API support)")
	else
		health.error("Neovim " .. version_str .. " is too old (0.9+ required)")
	end
end

--- Check wiki and daily directories exist
local function check_directories()
	health.start("Wiki directories")

	if not config.wikidir then
		health.error("Wiki directory not set (has setup() been called?)", {
			"Call require('womwiki').setup({ path = '~/your/wiki' })",
		})
		return
	end

	if vim.fn.isdirectory(config.wikidir) == 1 then
		health.ok("Wiki directory: " .. config.wikidir)
	else
		health.error("Wiki directory does not exist: " .. config.wikidir, {
			"Create it with: mkdir -p " .. config.wikidir,
		})
	end

	if not config.dailydir then
		health.warn("Daily directory not set")
	elseif vim.fn.isdirectory(config.dailydir) == 1 then
		health.ok("Daily directory: " .. config.dailydir)
	else
		health.warn("Daily directory does not exist: " .. config.dailydir, {
			"It will be created automatically when you open a daily note",
		})
	end
end

--- Check picker plugin availability
local function check_picker()
	health.start("Picker plugin")

	local pickers = {
		{ name = "snacks.picker", mod = "snacks" },
		{ name = "fzf-lua", mod = "fzf-lua" },
		{ name = "mini.pick", mod = "mini.pick" },
		{ name = "telescope", mod = "telescope" },
	}

	local found = {}
	for _, p in ipairs(pickers) do
		if pcall(require, p.mod) then
			table.insert(found, p.name)
		end
	end

	if #found > 0 then
		health.ok("Picker available: " .. table.concat(found, ", "))
	else
		health.warn("No picker plugin found", {
			"Install one of: snacks, fzf-lua, mini.pick, or telescope.nvim",
			"Some features (file browsing, tag search) require a picker",
		})
	end

	if config.config.picker then
		health.info("Configured picker preference: " .. config.config.picker)
	end
end

--- Check ripgrep availability
local function check_ripgrep()
	health.start("External tools")
	if vim.fn.executable("rg") == 1 then
		health.ok("ripgrep (rg) found")
	else
		health.info("ripgrep (rg) not found (optional; Lua fallback used for tag indexing)")
	end
end

--- Check completion plugin availability
local function check_completion()
	health.start("Completion plugin")
	local found = {}
	if pcall(require, "blink.cmp") then
		table.insert(found, "blink.cmp")
	end
	if pcall(require, "cmp") then
		table.insert(found, "nvim-cmp")
	end

	if #found > 0 then
		health.info("Completion available: " .. table.concat(found, ", "))
	else
		health.info("No completion plugin found (optional; install blink.cmp or nvim-cmp for link/tag completion)")
	end
end

function M.check()
	check_neovim_version()
	check_directories()
	check_picker()
	check_ripgrep()
	check_completion()
end

return M

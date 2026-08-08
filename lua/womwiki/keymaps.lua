-- womwiki/keymaps.lua
-- Default global keymaps, installed after setup so they can be configured.

local M = {}

local installed = {}

local function clear_installed()
	for _, mapping in ipairs(installed) do
		for _, mode in ipairs(mapping.modes) do
			local current = vim.fn.maparg(mapping.lhs, mode, false, true)
			if current.desc == mapping.desc then
				pcall(vim.keymap.del, mode, mapping.lhs)
			end
		end
	end
	installed = {}
end

local function set(modes, lhs, rhs, desc)
	if not lhs or lhs == false then
		return
	end

	vim.keymap.set(modes, lhs, rhs, { desc = desc })
	table.insert(installed, { modes = modes, lhs = lhs, desc = desc })
end

--- Install configured default keymaps.
--- @param womwiki table Public womwiki API
--- @param opts womwiki.KeymapsConfig
function M.setup(womwiki, opts)
	clear_installed()

	if vim.g.womwiki_disable_mappings or not opts.enabled then
		return
	end

	set({ "n", "v" }, opts.menu, womwiki.picker, "womwiki menu")
end

return M

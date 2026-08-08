local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

local keymaps = require("womwiki.keymaps")

local T = new_set({
	hooks = {
		pre_case = function()
			vim.g.womwiki_disable_mappings = false
			keymaps.setup({}, { enabled = false })
		end,
		after_case = function()
			keymaps.setup({}, { enabled = false })
			vim.g.womwiki_disable_mappings = true
		end,
	},
})

local function test_keymaps()
	return {
		enabled = true,
		menu = "<F20>",
	}
end

local fake_womwiki = {
	picker = function() end,
	backlinks = function() end,
	show_graph = function() end,
	capture_with_location = function() end,
	capture_visual = function() end,
	inbox = function() end,
}

T["installs the picker mapping"] = function()
	keymaps.setup(fake_womwiki, test_keymaps())

	expect.equality(vim.fn.maparg("<F20>", "n", false, true).desc, "womwiki menu")
	expect.equality(vim.fn.maparg("<F20>", "v", false, true).desc, "womwiki menu")
end

T["does not install obsolete leaf mappings"] = function()
	keymaps.setup(fake_womwiki, test_keymaps())

	expect.equality(vim.fn.maparg("<F21>", "n", false, true).lhs, nil)
end

T["does not install mappings when disabled"] = function()
	local opts = test_keymaps()
	opts.enabled = false
	keymaps.setup(fake_womwiki, opts)

	expect.equality(vim.fn.maparg("<F20>", "n", false, true).lhs, nil)
end

return T

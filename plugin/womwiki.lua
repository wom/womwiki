-- Keymaps for womwiki

local has_womwiki, womwiki = pcall(require, "womwiki")
if not has_womwiki then
	return
end

-- Default keymaps
-- You can disable these by setting vim.g.womwiki_disable_mappings = true
if not vim.g.womwiki_disable_mappings then
	vim.keymap.set({ "n", "v" }, "<leader>w", womwiki.picker, { desc = "womwiki!" })
	vim.keymap.set("n", "<leader>wb", womwiki.backlinks, { desc = "womwiki backlinks" })
	vim.keymap.set("n", "<leader>wg", womwiki.show_graph, { desc = "womwiki graph view" })
	vim.keymap.set("n", "<leader>wq", womwiki.capture_with_location, { desc = "womwiki quick capture" })
	vim.keymap.set("v", "<leader>wq", womwiki.capture_visual, { desc = "womwiki capture selection" })
	vim.keymap.set("n", "<leader>wi", womwiki.inbox, { desc = "womwiki inbox" })
end

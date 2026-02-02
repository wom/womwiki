-- womwiki/config.lua
-- Shared configuration and state management

local M = {}

M.version = "0.0.1"

-- Default configuration
M.config = {
	path = os.getenv("HOME") .. "/src/wiki",
	picker = nil, -- Optional: 'telescope', 'mini', 'fzf', 'snacks'
	inbox = {
		file = "inbox.md", -- relative to wiki root
		format = "- [ ] {{ datetime }} - {{ text }}",
		datetime_format = "%Y-%m-%d %H:%M",
	},
	completion = {
		enabled = true,
		include_headings = true,
		max_results = 50,
	},
}

-- Resolved paths (set by update_paths)
M.wikidir = nil
M.dailydir = nil

-- Update resolved paths from config
function M.update_paths()
	local symlink_path = vim.fn.expand(M.config.path)
	M.wikidir = vim.uv.fs_realpath(symlink_path) or symlink_path
	M.dailydir = M.wikidir .. "/daily"
end

-- Setup function - merge user config and update paths
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	M.update_paths()
end

-- Initialize with defaults
M.update_paths()

return M

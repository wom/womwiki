-- womwiki/config.lua
-- Shared configuration and state management

--- @class (exact) womwiki.InboxConfig
--- @field file string Inbox filename relative to wiki root
--- @field format string Entry format template (supports {{ datetime }}, {{ text }})
--- @field datetime_format string strftime format for {{ datetime }}

--- @class (exact) womwiki.CompletionConfig
--- @field enabled boolean Enable link/tag completion
--- @field include_headings boolean Include headings in completion results
--- @field max_results integer Maximum number of completion results
--- @field cache_ttl integer Seconds before file/tag caches expire (fallback; autocmd handles normal edits)

--- @class (exact) womwiki.WikilinksConfig
--- @field enabled boolean Support [[wikilink]] syntax
--- @field spaces_to string? Convert spaces in link names: "-", "_", or nil to keep spaces
--- @field confirm_create boolean Confirm before creating new files from links

--- @class (exact) womwiki.TagsConfig
--- @field enabled boolean Support #tags and frontmatter tags
--- @field inline_pattern string Lua pattern for inline tags
--- @field use_frontmatter boolean Parse YAML frontmatter for tags

--- @class (exact) womwiki.Config
--- @field path string Path to wiki root directory
--- @field picker string? Picker backend: "telescope", "mini", "fzf", "snacks", or nil to auto-detect
--- @field inbox womwiki.InboxConfig
--- @field completion womwiki.CompletionConfig
--- @field wikilinks womwiki.WikilinksConfig
--- @field tags womwiki.TagsConfig
--- @field default_link_style "markdown"|"wikilink"

local M = {}

--- @type womwiki.Config
M.config = {
	path = os.getenv("HOME") .. "/src/wiki",
	picker = nil,
	inbox = {
		file = "inbox.md",
		format = "- [ ] {{ datetime }} - {{ text }}",
		datetime_format = "%Y-%m-%d %H:%M",
	},
	completion = {
		enabled = true,
		include_headings = true,
		max_results = 50,
		cache_ttl = 300,
	},
	wikilinks = {
		enabled = true,
		spaces_to = "-",
		confirm_create = true,
	},
	tags = {
		enabled = true,
		inline_pattern = "#([%w_-]+)",
		use_frontmatter = true,
	},
	default_link_style = "markdown",
}

--- Resolved wiki root path (set by update_paths)
--- @type string?
M.wikidir = nil

--- Resolved daily notes path (set by update_paths)
--- @type string?
M.dailydir = nil

function M.update_paths()
	local symlink_path = vim.fn.expand(M.config.path)
	M.wikidir = vim.uv.fs_realpath(symlink_path) or symlink_path
	M.dailydir = M.wikidir .. "/daily"
end

--- @param opts womwiki.Config.Partial?
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	M.update_paths()
end

-- Initialize with defaults
M.update_paths()

return M

-- womwiki/types.lua
-- Partial (user-facing) type definitions for setup()
-- This file is annotation-only; it exists so LuaLS can discover the partial types.
-- The ", {}" multi-inheritance trick makes all inherited fields optional.

--- @class (exact) womwiki.Config.Partial : womwiki.Config, {}
--- @field path? string
--- @field picker? string
--- @field inbox? womwiki.InboxConfig.Partial
--- @field completion? womwiki.CompletionConfig.Partial
--- @field wikilinks? womwiki.WikilinksConfig.Partial
--- @field tags? womwiki.TagsConfig.Partial
--- @field default_link_style? "markdown"|"wikilink"

--- @class (exact) womwiki.InboxConfig.Partial : womwiki.InboxConfig, {}

--- @class (exact) womwiki.CompletionConfig.Partial : womwiki.CompletionConfig, {}

--- @class (exact) womwiki.WikilinksConfig.Partial : womwiki.WikilinksConfig, {}

--- @class (exact) womwiki.TagsConfig.Partial : womwiki.TagsConfig, {}

return {}

# womwiki

[![CI](https://github.com/wom/womwiki/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/wom/womwiki/actions/workflows/ci.yml)

A Neovim plugin for managing your personal wiki.

<p align="center">
  <img src="demo.gif" alt="womwiki demo" width="800" />
</p>

## Features

- **Daily notes** — templated journal entries with todo rollover between days
- **Wikilinks** — `[[Page Name]]` syntax with fuzzy resolution and create-on-follow
- **Link graph** — visualize connections, find orphans, hubs, and broken links
- **Backlinks** — instantly find every file that links to the current note
- **Tags** — inline `#tags` and YAML frontmatter, browse and filter by tag
- **Quick capture** — grab a thought to your inbox with a source link back to where you were
- **Calendar** — visual month view to navigate daily notes
- **Rename & refactor** — rename a file and update all inbound links automatically
- **Completion** — autocomplete links, headings, and tags (blink.cmp + nvim-cmp)
- **Multi-picker** — works with snacks, fzf-lua, mini.pick, or telescope (auto-detected)

## Dependencies

One of the following picker plugins is required:
- [snacks.nvim](https://github.com/folke/snacks.nvim) (modern, fast) — **preferred**
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (fast, feature-rich)
- [mini.pick](https://github.com/echasnovski/mini.nvim) (lightweight, modern)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (most popular)

The plugin auto-detects which one is available (in the order above).

## Optional Enhancements

For improved markdown viewing experience:
- [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) - Beautiful inline markdown rendering with proper formatting, checkboxes, and code blocks

For table editing in wiki files:
- [table.vim](https://github.com/numEricL/table.vim) - Auto-aligned markdown table editing with cell navigation and sorting. Automatically configured for markdown style in wiki buffers when detected.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "wom/womwiki",
  dependencies = {
    "folke/snacks.nvim", -- Preferred picker (auto-detected)
    -- Alternatives (uncomment to use instead):
    -- "ibhagwan/fzf-lua",
    -- "echasnovski/mini.nvim",
    -- "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("womwiki").setup({
      path = "~/wiki", -- Path to your wiki directory
    })
  end,
}
```

## Configuration

Default configuration with all options:

```lua
require("womwiki").setup({
  path = "~/src/wiki",              -- Path to your wiki directory
  picker = nil,                     -- "snacks", "fzf", "mini", "telescope", or nil (auto-detect)
  default_link_style = "markdown",  -- "markdown" or "wikilink" for new links

  inbox = {
    file = "inbox.md",                        -- Inbox file, relative to wiki root
    format = "- [ ] {{ datetime }} - {{ text }}", -- Entry format template
    datetime_format = "%Y-%m-%d %H:%M",       -- strftime format for {{ datetime }}
  },

  completion = {
    enabled = true,           -- Enable link/tag autocompletion
    include_headings = true,  -- Offer headings in completion (file.md#heading)
    max_results = 50,         -- Maximum completion results
    cache_ttl = 300,          -- Cache expiry in seconds (also invalidated on save)
  },

  wikilinks = {
    enabled = true,       -- Support [[wikilink]] syntax
    spaces_to = "-",      -- Convert spaces: "-", "_", or nil (keep spaces)
    confirm_create = true, -- Confirm before creating new files from links
  },

  tags = {
    enabled = true,              -- Support #tags and frontmatter tags
    inline_pattern = "#([%w_-]+)", -- Lua pattern for inline tags
    use_frontmatter = true,      -- Parse YAML frontmatter for tags
  },

  keymaps = {
    enabled = true,              -- Install default global mappings
    menu = "<leader>w",          -- Set to false to omit it
  },
})
```

## Keymaps

Global mappings are installed by `setup()` and can be configured through `keymaps` (or disabled with `keymaps.enabled = false`). The legacy `vim.g.womwiki_disable_mappings = true` is also supported.

- `<leader>w`: Open the wiki picker

### Wiki Menu Structure

The picker menu (`<leader>w` or `require("womwiki").picker()`) provides quick access to common operations:

**Top Level (Quick Actions):**
- Today/Close Daily - Open today's daily note or close it if already open
- Recent - Browse recently opened wiki files
- Calendar - Visual calendar view of daily notes
- Search - Search content across all wiki notes
- Create - Create a new wiki note

**Browse & Search submenu:**
- Browse All Notes - Browse all wiki files
- Browse Dailies - Browse daily note files
- Search Dailies - Search within daily notes by filename
- Yesterday - Open yesterday's daily note

**Analyze submenu:**
- Backlinks - Show files that link to current note
- Graph View - Visualize note connections
- Validate Links - Find broken/dangling links across the wiki

**Settings/Tools submenu:**
- Rename / Refactor - Rename a note and update all inbound links
- Edit Daily Template - Customize the template used for new daily notes
- Cleanup Empty Dailies - Remove empty daily notes that match the template

## Daily Note Templates

The plugin uses a customizable template for creating daily notes. Templates support the `{{ date }}` variable which is replaced with the date in YYYY-MM-DD format.

### Template Priority

The plugin searches for templates in the following order:
1. **Wiki template**: `<wikidir>/.templates/daily.md` (recommended)
2. **Config template**: `~/.config/nvim/templates/daily.templ` (legacy)
3. **Built-in default**: Used if no custom template exists

### Customizing the Template

Use the picker: `<leader>w` → `Tools` → `Edit Daily Template`

This will:
- Open your wiki template if it exists
- Create a new template from the built-in default if needed
- Automatically create the `.templates` directory in your wiki

### Default Template

```markdown
<!-- [« Prev](prev) | [Next »](next) -->
# {{ date }}
## Standup
* Vibe:
* ToDone:
* ToDo:
* Blocking:
## Log
```

The navigation line at the top allows jumping between daily notes:
- Position cursor on `Prev` or `Next` and press `Enter`
- Or use `[w` / `]w` keymaps to navigate

**Note:** Keep your template in your wiki directory (`<wikidir>/.templates/daily.md`) to make your wiki self-contained and portable.

Wiki Markdown buffer mappings (only files under the configured wiki path):
- `<leader>ml`: Convert word to link / cycle link format (`[text](file)` ↔ `[[file]]`)
- `<leader>mc`: Toggle checkbox
- `gf`: Follow markdown link (enhanced)
- `<CR>`: Follow markdown link

## Completion

womwiki provides link completion when typing `](`, `[[`, or `#` in markdown files. It supports both **nvim-cmp** and **blink.cmp**.

### blink.cmp Setup

```lua
{
  'saghen/blink.cmp',
  opts = {
    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer', 'womwiki' },
      providers = {
        womwiki = {
          name = 'womwiki',
          module = 'blink_womwiki',
          score_offset = 10, -- Boost wiki completions
          enabled = function()
            return vim.bo.filetype == 'markdown'
          end,
        },
      },
    },
  },
}
```

### nvim-cmp Setup

The source is automatically registered when nvim-cmp is detected. To manually configure:

```lua
{
  'hrsh7th/nvim-cmp',
  config = function()
    local cmp = require('cmp')
    cmp.setup({
      sources = cmp.config.sources({
        { name = 'womwiki' },
        -- ... other sources
      }),
    })
  end,
}
```

### Completion Features

- **File completion**: Type `[link text](` or `[[` to get wiki file suggestions
- **Heading completion**: Type `[link](file.md#` to complete headings within that file
- **Tag completion**: Type `#` (after text) to complete existing tags
- Fuzzy matching on both filename and title
- Results are cached and rebuild asynchronously — completion never blocks the editor

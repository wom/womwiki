# womwiki

A Neovim plugin for managing your personal wiki.

## Dependencies

One of the following picker plugins is required:
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (fast, feature-rich) - **default**
- [mini.pick](https://github.com/echasnovski/mini.nvim) (lightweight, modern)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (most popular)

The plugin will automatically detect which one is available and use it.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "wom/womwiki",
  dependencies = {
    "ibhagwan/fzf-lua", -- Default picker (recommended)
    -- Alternatives (uncomment to use instead):
    -- "echasnovski/mini.nvim",
    -- "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("womwiki").setup({
      path = "~/src/wiki", -- Path to your wiki
    })
  end,
}
```

## Configuration

Default configuration:

```lua
require("womwiki").setup({
  path = "~/src/wiki", -- Default path
  picker = nil, -- Optional: 'telescope', 'mini', or 'fzf'. Defaults to auto-detect.
})
```

## Keymaps

Global mappings (can be disabled by setting `vim.g.womwiki_disable_mappings = true`):
- `<leader>w`: Open wiki picker
- `<leader>wb`: Show backlinks
- `<leader>wg`: Show graph view

Markdown buffer mappings:
- `<leader>ml`: Convert word to markdown link
- `<leader>mc`: Toggle checkbox
- `gf`: Follow markdown link (enhanced)
- `<CR>`: Follow markdown link

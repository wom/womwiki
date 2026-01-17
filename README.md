# womwiki

A Neovim plugin for managing your personal wiki.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "wom/womwiki",
  config = function()
    require("womwiki").setup({
      path = "~/src/wiki", -- Path to your wiki
    })
  end,
  ft = "markdown",
}
```

## Configuration

Default configuration:

```lua
require("womwiki").setup({
  path = "~/src/wiki", -- Default path
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

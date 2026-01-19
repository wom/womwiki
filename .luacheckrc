-- Luacheck configuration for Neovim plugin
std = "lua51"
globals = { "vim" }
max_line_length = false
ignore = {
    "212", -- Unused argument (common in callbacks)
    "631", -- Line is too long (let formatter handle)
}

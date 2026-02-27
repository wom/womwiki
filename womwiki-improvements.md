# womwiki Plugin Improvement Suggestions

**Date:** 2025-12-05  
**Files Reviewed:** `lua/utils/womwiki.lua`, `ftplugin/markdown.lua`

> **✅ Status Update (2026-01):** Many suggestions in this document have been
> implemented. The modular architecture from Priority 3.1 is complete — see
> `lua/womwiki/{config,utils,daily,calendar,capture,files,menu,graph}.lua`.
> Path references and line numbers below are from the original monolithic file.

## Overview

Your note-taking plugin is well-structured with good functionality. Below are prioritized suggestions for cleanup and improvement.

---

## Priority 1: High Impact Changes

### 1.1 Reduce Excessive Notifications

**Issue:** Too many `vim.notify()` calls clutter the UI and reduce usability.

**Files Affected:**
- `lua/utils/womwiki.lua` lines 176, 190, 191, 192, 194
- `ftplugin/markdown.lua` line 4

**Recommendations:**
- Remove debug notifications:
  - Line 176: `vim.notify('swapping ' .. key .. ' for ' .. value)`
  - Line 190: `vim.notify('date is ' .. date)`
  - Line 191: `vim.notify('File exists, opening it.')`
  - Line 194: `vim.notify('creating file.')`
- Remove: Line 4 in `markdown.lua`: `vim.notify('FT loaded: markdown.lua')`
- Keep only important user-facing notifications (errors, confirmations, important info)

**Impact:** Cleaner UI, less noise

---

### 1.2 Fix Deprecated API Calls

**Issue:** Using deprecated `nvim_buf_set_option` API

**Files Affected:**
- `lua/utils/womwiki.lua` lines 304, 305, 354, 355, 449, 450

**Current Code:**
```lua
vim.api.nvim_buf_set_option(buf, 'modifiable', false)
vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
```

**Recommended Fix:**
```lua
vim.bo[buf].modifiable = false
vim.bo[buf].buftype = 'nofile'
```

**Impact:** Future-proof code, removes deprecation warnings

---

### 1.3 Consolidate Repeated File Opening Logic

**Issue:** File opening with wiki setup appears in multiple places

**Locations:**
- Lines 100-103 (create_file)
- Lines 111-113 (create_file overwrite path)
- Lines 148-150 (recent)
- Lines 203-205 (open_daily)
- Lines 166-168, 179-181, 207-210 (follow_markdown_link in markdown.lua)

**Recommended Solution:**
```lua
-- Add helper function at top of womwiki.lua module
local function open_wiki_file(path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    vim.b.womwiki = true
    vim.cmd("lcd " .. vim.fn.fnameescape(M.wikidir))
end
```

**Impact:** DRY principle, easier maintenance, consistent behavior

---

## Priority 2: Code Quality

### 2.1 Variable Shadowing

**Issue:** Variable `subs` is shadowed in loop

**File:** `lua/utils/womwiki.lua` line 174

**Current Code:**
```lua
local function create_file_with_template(filename, template, subs)
    -- ...
    for _, subs in ipairs(subs) do  -- shadows parameter
        local key, value = subs[1], subs[2]
```

**Recommended Fix:**
```lua
for _, sub_pair in ipairs(subs) do
    local key, value = sub_pair[1], sub_pair[2]
```

**Impact:** Avoid confusion, better code clarity

---

### 2.2 Inconsistent `.md` Extension Handling

**Issue:** Multiple places check/add `.md` extension inconsistently

**Locations:**
- Line 86-88 in womwiki.lua
- Line 159-161 in markdown.lua
- Line 171-173 in markdown.lua
- Line 196-198 in markdown.lua

**Recommended Solution:**
```lua
-- Add helper function
local function ensure_md_extension(filename)
    if not filename:match("%.md$") then
        return filename .. ".md"
    end
    return filename
end
```

**Impact:** Consistent behavior, less duplication

---

### 2.3 Error Handling for Dependencies

**Issue:** No check if fzf-lua is available

**Locations:** Multiple functions (wiki, dailies, recent, search)

**Recommended Solution:**
```lua
local function require_fzf()
    local ok, fzf = pcall(require, 'fzf-lua')
    if not ok then
        vim.notify("fzf-lua not installed", vim.log.levels.ERROR)
        return nil
    end
    return fzf
end

-- Then use it:
function M.wiki()
    local fzf = require_fzf()
    if not fzf then return end
    fzf.files({ cwd = M.wikidir, fzf_opts = { ['--sort'] = true } })
end
```

**Impact:** Better error messages, graceful degradation

---

## Priority 3: Architecture & Organization

### 3.1 Extract Calendar Module

**Issue:** Calendar function is 200+ lines, making womwiki.lua harder to navigate

**Current:** Lines 218-426 in womwiki.lua

**Recommended Structure:**
```
lua/utils/
├── womwiki.lua          (main interface)
├── womwiki/
│   ├── calendar.lua     (calendar UI)
│   ├── menu.lua         (menu system)
│   └── files.lua        (file operations)
```

**Benefits:**
- Better organization
- Easier testing
- Clearer responsibilities

---

### 3.2 Separate File Operations from UI

**Issue:** Mixed concerns (file I/O + UI rendering)

**Examples:**
- `create_file()` mixes vim.ui.select with file creation
- `cleanup()` mixes file scanning with UI preview

**Recommended Pattern:**
```lua
-- Pure functions for file operations
local function scan_unmodified_dailies()
    -- returns list of files
end

-- UI functions use the pure functions
function M.cleanup()
    local files = scan_unmodified_dailies()
    show_cleanup_preview(files, function()
        delete_files(files)
    end)
end
```

**Impact:** Easier testing, better code organization

---

## Priority 4: Performance Optimizations

### 4.1 Cache Existing Dailies in Calendar

**Issue:** `get_existing_dailies()` called on every calendar render

**Location:** Line 267 (called in render_calendar)

**Recommended Fix:**
```lua
local function show_calendar(year, month, selected_day)
    local existing_dailies = get_existing_dailies()  -- cache once
    
    local function render_calendar(year, month, selected_day)
        -- use cached existing_dailies instead of calling get_existing_dailies()
        -- ...
    end
    -- rest of function
end
```

**Impact:** Faster calendar navigation

---

### 4.2 Use vim.uv.fs_scandir More Efficiently

**Issue:** Could use async scanning for large directories

**Current:** Synchronous scanning in `list_files()` and `get_wiki_folders()`

**Future Enhancement:** Consider async scanning if directory grows large
```lua
-- Example pattern:
local function list_files_async(callback)
    vim.uv.fs_scandir(M.dailydir, function(err, handle)
        -- async processing
    end)
end
```

**Impact:** Non-blocking for large wikis

---

## Priority 5: Feature Enhancements

### 5.1 Add Telescope.nvim Support

**Benefit:** Many users prefer telescope over fzf-lua

**Recommended Implementation:**
```lua
local function get_picker()
    if pcall(require, 'telescope') then
        return 'telescope'
    elseif pcall(require, 'fzf-lua') then
        return 'fzf'
    else
        vim.notify("No picker installed (telescope/fzf-lua)", vim.log.levels.ERROR)
        return nil
    end
end

function M.wiki()
    local picker = get_picker()
    if picker == 'telescope' then
        require('telescope.builtin').find_files({ cwd = M.wikidir })
    elseif picker == 'fzf' then
        require('fzf-lua').files({ cwd = M.wikidir })
    end
end
```

---

### 5.4 Link Autocompletion

**Enhancement:** Add completion for wiki links when typing `[text]()`

**Implementation Idea:**
```lua
-- In ftplugin/markdown.lua
vim.api.nvim_create_autocmd('CompleteDone', {
    buffer = 0,
    callback = function()
        -- Detect [text](| cursor position
        -- Offer file completion from wiki
    end
})
```

---

### 5.5 Backlinks Support

**Enhancement:** Show which files link to current file

**Implementation Idea:**
```lua
function M.show_backlinks()
    local current_file = vim.fn.expand('%:t:r')  -- filename without extension
    
    -- Search for links to current file
    require('fzf-lua').grep({
        search = '\\[.*\\]\\(' .. current_file,
        cwd = M.wikidir
    })
end
```

---

## Priority 6: Minor Improvements

### 6.1 Better Window Sizing

**Current:** Fixed sizes for popups

**Enhancement:** Make responsive to terminal size with better min/max
```lua
local function get_centered_window_opts(width_pct, height_pct, min_w, min_h)
    local width = math.max(min_w, math.floor(vim.o.columns * width_pct))
    local height = math.max(min_h, math.floor(vim.o.lines * height_pct))
    
    return {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        style = "minimal",
        border = "rounded",
    }
end
```

---

### 6.2 Add Configuration Options

**Enhancement:** Make paths and behavior configurable

**Example:**
```lua
M.config = {
    wikidir = os.getenv("HOME") .. '/src/wiki',
    dailydir_name = 'daily',
    template_path = os.getenv("HOME") .. '/.config/nvim/templates/daily.templ',
    default_keybinds = true,
    picker = 'auto',  -- 'fzf', 'telescope', or 'auto'
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend('force', M.config, opts or {})
    M.dailydir = M.config.wikidir .. '/' .. M.config.dailydir_name
end
```

---

### 6.3 Better Date Navigation in Calendar

**Enhancement:** Add jump to specific date

**Add keybinding:**
- `g` - Jump to specific date (prompt for YYYY-MM-DD)

---

### 6.4 WSL URL Opening

**Current:** Good WSL detection in markdown.lua

**Enhancement:** Extract to utility function for reuse
```lua
-- In womwiki.lua
function M.open_url(url)
    local is_wsl = vim.fn.has('wsl') == 1 or vim.fn.exists('$WSL_DISTRO_NAME') == 1
    
    if is_wsl then
        vim.fn.system({'cmd.exe', '/c', 'start', url})
    else
        vim.ui.open(url)
    end
end
```

---

## Testing Recommendations

### Add Basic Tests

Consider adding tests for:
1. File creation logic
2. Link parsing in markdown.lua
3. Date offset calculations
4. Template substitution

**Test Framework Suggestion:**
- `plenary.nvim` (popular in neovim plugins)

---

## Documentation Needs

### Add README

Include:
- Installation instructions
- Dependencies (fzf-lua)
- Configuration options
- Keybinding reference
- Template format documentation

### Add Inline Documentation

Use LuaLS annotations:
```lua
---@class Womwiki
---@field wikidir string Path to wiki root
---@field dailydir string Path to daily notes

---Open a daily note with offset
---@param days_offset number? Days offset from today (default: 0)
function M.open_daily(days_offset)
```

---

## Security Considerations

### Path Traversal

**Current:** Generally good, using `vim.fn.fnameescape()`

**Verify:** User input in `create_file()` can't escape wiki directory

### File Deletion

**Current:** Cleanup has preview + confirmation

**Good:** Consider adding undo/trash instead of permanent deletion

---

## Summary of Quick Wins

**High impact, low effort changes to do first:**

1. Remove debug notifications (5 min)
2. Fix deprecated API calls (10 min)
3. Add `open_wiki_file()` helper (15 min)
4. Fix variable shadowing (2 min)
5. Add dependency check for fzf-lua (10 min)

**Total estimated time:** ~45 minutes for significant improvement

---

## Implementation Priority

1. **Phase 1 (Quick Wins):** Items 1-5 from summary above
2. **Phase 2 (Stability):** Error handling, testing
3. **Phase 3 (Architecture):** Module extraction, separation of concerns
4. **Phase 4 (Features):** Telescope support, backlinks, configuration
5. **Phase 5 (Polish):** Documentation, tests, performance optimization

---

## Conclusion

Your plugin has solid functionality and good UX design. The main improvements focus on:
- **Code quality:** Remove debug code, fix deprecations
- **Maintainability:** Better organization, DRY principle
- **Robustness:** Error handling, dependency checks
- **Features:** Telescope support, backlinks, configurability

The suggested changes are backward-compatible and can be implemented incrementally.

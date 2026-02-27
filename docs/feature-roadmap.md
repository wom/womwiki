# womwiki Feature Roadmap

A staged roadmap for enhancing womwiki with features tailored for software engineer note-taking workflows.

Each stage is designed to be implemented independently, though some build upon previous stages where noted.

### Maintenance Checklist

After completing each stage:
- [ ] Update `doc/womwiki.txt` with new features
- [ ] Update this roadmap to mark stage complete

---

## Stage 1: `:help` Documentation Generation ✅

**Status**: Complete

**Summary**: Create proper Neovim help documentation (`doc/womwiki.txt`) so users can access documentation via `:help womwiki`.

**Completed**:
- Created `doc/womwiki.txt` with full vimdoc documentation
- Documented all commands, keybindings, configuration options
- Included calendar, graph view, backlinks, and template documentation
- Added roadmap section for planned features

**To generate helptags**: Run `:helptags doc/` or restart Neovim.

**Dependencies**: None

---

## Stage 2: Quick Capture / Inbox System ✅

**Status**: Complete

**Summary**: A single keybind to instantly capture a thought to an inbox file without leaving the current context.

**Completed**:
- Added `capture()` function with prompt input
- Added `capture_visual()` for capturing visual selection
- Added `inbox()` to open inbox file
- Added configurable inbox settings (file, format, datetime_format)
- Added `<leader>wq` keybinding (normal: prompt, visual: capture selection)
- Added `<leader>wi` keybinding to open inbox
- Added Quick Capture to main menu and submenu
- Updated `doc/womwiki.txt` with documentation

**Configuration**:
```lua
require("womwiki").setup({
  inbox = {
    file = "inbox.md",           -- relative to wiki root
    format = "- [ ] {{ datetime }} - {{ text }}",
    datetime_format = "%Y-%m-%d %H:%M",
  },
})
```

**Dependencies**: None

---

## Stage 3: Multiple Templates

**Summary**: Support multiple named templates for different note types beyond daily notes.

**Motivation**: Engineers create diverse documents: meeting notes, ADRs (Architecture Decision Records), 1:1 notes, project kickoffs, incident postmortems, learning logs. Each benefits from a consistent structure.

**Implementation**:

1. **Template directory**: `<wiki>/.templates/` (already exists for `daily.md`)

2. **Built-in templates** (create if not present):
   - `daily.md` – Existing standup format
   - `meeting.md` – Attendees, agenda, notes, action items
   - `adr.md` – Status, context, decision, consequences
   - `1on1.md` – Topics, feedback, action items, notes
   - `project.md` – Overview, goals, milestones, links
   - `incident.md` – Timeline, impact, root cause, remediation

3. **Commands**:
   - `:WomNew` – Interactive template picker → filename prompt → create
   - `:WomNew meeting` – Create from specific template
   - `:WomNew meeting standup-2026-01-28` – Template + filename

4. **Template variables**:
   ```
   {{ date }}        → 2026-01-28
   {{ datetime }}    → 2026-01-28 14:32
   {{ title }}       → Filename without extension
   {{ time }}        → 14:32
   {{ year }}        → 2026
   {{ month }}       → 01
   {{ day }}         → 28
   ```

5. **Configuration**:
   ```lua
   require("womwiki").setup({
     templates = {
       dir = ".templates",          -- relative to wiki root
       default = "note",            -- default template for :WomNew
     },
   })
   ```

**Example meeting template** (`.templates/meeting.md`):
```markdown
# {{ title }}

**Date**: {{ date }}
**Attendees**: 

## Agenda

- 

## Notes



## Action Items

- [ ] 
```

**Dependencies**: None

---

## Stage 4: Link Autocompletion ✅

**Status**: Complete

**Summary**: When typing `[text](`, offer fuzzy completion of existing wiki pages.

**Completed**:
- Created `lua/cmp_womwiki/init.lua` nvim-cmp source
- Added built-in omnifunc completion (`<C-x><C-o>`) as fallback
- Completion triggers after typing `](`
- Shows file paths with titles from first H1 heading
- Heading completion: type `file.md#` to complete headings within that file
- Added `completion` config options (enabled, include_headings, max_results)
- Updated `doc/womwiki.txt` with completion documentation

**Configuration**:
```lua
require("womwiki").setup({
  completion = {
    enabled = true,
    include_headings = true,
    max_results = 50,
  },
})
```

**Usage**:
- nvim-cmp: Add `{ name = "womwiki" }` to sources (auto-registers on markdown files)
- Built-in: `<C-x><C-o>` triggers omnifunc completion

**Dependencies**: 
- Optional: nvim-cmp for best experience
- Works standalone with built-in completion

---

## Stage 5: `[[Wikilinks]]` Support

**Summary**: Support `[[Page Name]]` syntax alongside standard markdown links for faster note creation.

**Motivation**: Wikilinks are faster to type than `[text](path.md)`. Popular in Obsidian, Notion, and other knowledge tools. Reduces friction when linking, especially for pages that don't exist yet.

**Implementation**:

1. **Syntax**: `[[Page Name]]` or `[[Page Name|display text]]`

2. **Resolution rules**:
   - Exact match: `[[my-note]]` → `my-note.md`
   - Case-insensitive search if no exact match
   - Spaces to hyphens: `[[My Note]]` → `my-note.md`
   - Subdirectory search: finds `projects/my-note.md`

3. **Following wikilinks**:
   - Extend `follow_markdown_link()` in ftplugin to handle `[[...]]`
   - `gf` and `<CR>` work on wikilinks
   - Offer to create if page doesn't exist

4. **Highlighting**:
   - Add Treesitter queries or manual syntax for `[[...]]`
   - Different highlight for existing vs non-existing pages (optional)

5. **Conversion commands**:
   - `:WomWikilinkToMarkdown` – Convert `[[Page]]` to `[Page](page.md)`
   - `:WomMarkdownToWikilink` – Convert `[text](file.md)` to `[[file]]`

6. **Backlinks integration**:
   - Update `build_link_graph()` to parse wikilinks
   - Include wikilinks in backlink search

7. **Configuration**:
   ```lua
   require("womwiki").setup({
     wikilinks = {
       enabled = true,
       auto_create = true,         -- create on follow if missing
       spaces_to = "-",            -- or "_" or " " (keep spaces)
     },
   })
   ```

**Dependencies**: 
- Stage 1 (docs should cover wikilink syntax)
- Modifies backlinks (existing feature)

---

## Stage 6: Tags & Frontmatter

**Summary**: Support `#tags` inline and/or YAML frontmatter for categorizing notes.

**Motivation**: Tags enable filtering, searching, and visualizing notes by topic. Engineers can tag by project, technology, status, or any taxonomy. Essential for scaling a wiki beyond dozens of notes.

**Implementation**:

1. **Tag formats supported**:
   - Inline: `#tag` anywhere in document
   - Frontmatter:
     ```yaml
     ---
     tags: [rust, debugging, performance]
     ---
     ```

2. **Commands**:
   - `:WomTags` – List all tags in wiki with counts
   - `:WomTag <tag>` – Search/filter notes by tag
   - `:WomTagAdd <tag>` – Add tag to current file (frontmatter or inline)

3. **Picker integration**:
   - Tag picker: select tag → shows all notes with that tag
   - Multi-tag filter: `#rust AND #debugging`

4. **Graph integration**:
   - Color nodes by tag in graph view
   - Filter graph to show only tagged subset
   - Tag cloud visualization

5. **Frontmatter parsing**:
   ```lua
   local function parse_frontmatter(bufnr)
     local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 20, false)
     -- Parse YAML between --- delimiters
     -- Return { tags = {...}, title = "...", ... }
   end
   ```

6. **Tag highlighting**:
   - Highlight `#tag` with distinct color
   - Treesitter or manual syntax

7. **Configuration**:
   ```lua
   require("womwiki").setup({
     tags = {
       enabled = true,
       inline_pattern = "#(%w+)",   -- regex for inline tags
       use_frontmatter = true,
     },
   })
   ```

**Dependencies**: None (enhances graph view from existing features)

---

## Stage 7: Rename & Refactor

**Summary**: Rename a wiki file and automatically update all backlinks referencing it.

**Motivation**: Wiki files inevitably need renaming as understanding evolves. Without automated backlink updates, renames break the link graph. This is table-stakes for wiki maintenance at scale.

**Implementation**:

1. **Commands**:
   - `:WomRename <newname>` – Rename current file, update all backlinks
   - `:WomMove <newpath>` – Move to different directory, update backlinks

2. **Rename process**:
   ```
   1. Parse new name/path
   2. Find all backlinks to current file (reuse backlinks search)
   3. Preview changes: show files that will be modified
   4. Confirm with user
   5. Update all references (markdown links + wikilinks)
   6. Rename/move the file
   7. Report results
   ```

3. **Reference update logic**:
   - `[text](old-path.md)` → `[text](new-path.md)`
   - `[[Old Name]]` → `[[New Name]]` (if wikilinks enabled)
   - Handle relative paths correctly

4. **Preview UI**:
   ```
   Renaming: projects/old-name.md → projects/new-name.md
   
   Files to update (3):
     index.md:15        [link](projects/old-name.md)
     daily/2026-01-28.md:42  [[old-name]]
     projects/readme.md:8    [see also](old-name.md)
   
   Proceed? (y/n)
   ```

5. **Safety features**:
   - Dry-run mode (preview only)
   - Undo support (store original state)
   - Git integration: stage changes automatically

6. **Configuration**:
   ```lua
   require("womwiki").setup({
     refactor = {
       confirm = true,            -- prompt before changes
       git_stage = false,         -- auto git add modified files
     },
   })
   ```

**Dependencies**: 
- Backlinks feature (existing)
- Stage 5 (if wikilinks enabled)

---

## Stage 8: Project-Linked Notes

**Summary**: Quickly open/create a note associated with the current git repository.

**Motivation**: Engineers work across multiple projects. Having a dedicated note per repo for TODOs, architecture notes, and context is invaluable. `:WomProject` from any buffer opens that repo's note.

**Implementation**:

1. **Commands**:
   - `:WomProject` – Open/create note for current repo
   - `:WomProjects` – List all project notes

2. **Note location**: `<wiki>/projects/<repo-name>.md`

3. **Repo detection**:
   ```lua
   local function get_repo_name()
     local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
     if git_root then
       return vim.fn.fnamemodify(git_root, ":t")  -- basename
     end
     return nil
   end
   ```

4. **Project template** (`.templates/project.md`):
   ```markdown
   # {{ title }}

   **Repository**: {{ repo_url }}
   **Created**: {{ date }}

   ## Overview



   ## Quick Links

   - [ ] 

   ## Notes

   ```

5. **Template variables for projects**:
   - `{{ repo_name }}` – Repository basename
   - `{{ repo_url }}` – Remote URL (if available)
   - `{{ repo_path }}` – Local filesystem path

6. **Configuration**:
   ```lua
   require("womwiki").setup({
     projects = {
       dir = "projects",           -- relative to wiki root
       template = "project",       -- template name
     },
   })
   ```

7. **Optional enhancements**:
   - Show project note in sidebar/split
   - Link to GitHub/GitLab issues
   - Auto-populate with README excerpt

**Dependencies**: 
- Stage 3 (templates)

---

## Stage 9: Heading Search

**Summary**: Search and jump to headings across all wiki files.

**Motivation**: Large wikis have hundreds of headings. Searching by heading structure lets you navigate by document organization rather than full-text keywords. "Jump to any Setup section" or "find all ## API headings."

**Implementation**:

1. **Commands**:
   - `:WomHeadings` – Fuzzy search all headings in wiki
   - `:WomOutline` – Show headings for current file (like symbols)

2. **Heading extraction**:
   ```lua
   local function extract_headings(filepath)
     local headings = {}
     for i, line in ipairs(vim.fn.readfile(filepath)) do
       local level, text = line:match("^(#+)%s+(.+)")
       if level then
         table.insert(headings, {
           level = #level,
           text = text,
           line = i,
           file = filepath,
         })
       end
     end
     return headings
   end
   ```

3. **Picker display**:
   ```
   ## Setup                    projects/myapp.md:45
   ### Installation            projects/myapp.md:52
   ## API Reference            docs/api.md:12
   # Daily Note 2026-01-28     daily/2026-01-28.md:1
   ```

4. **Filtering options**:
   - By heading level: only `##` headings
   - By directory: only `projects/` headings
   - By pattern: headings matching regex

5. **Current file outline**:
   - Floating window with heading tree
   - Jump to heading on select
   - Preview heading context

6. **Configuration**:
   ```lua
   require("womwiki").setup({
     headings = {
       max_level = 4,             -- ignore ##### and deeper
       exclude_daily = false,     -- include daily notes
     },
   })
   ```

**Dependencies**: None

---

## Stage 10: Code Block Runner

**Summary**: Execute fenced code blocks inline and capture output.

**Motivation**: Engineers write runbooks, tutorials, and literate documentation. Running code blocks without copy-pasting to a terminal keeps you in flow. Great for bash snippets, API examples, and reproducible docs.

**Implementation**:

1. **Commands**:
   - `:WomRunBlock` – Execute code block under cursor
   - `<leader>mr` – Keybind for run block (markdown buffer)

2. **Supported languages**:
   - `bash` / `sh` – Shell commands
   - `lua` – Execute in Neovim
   - `python` – Run with system python
   - `javascript` / `node` – Run with node
   - Extensible via config

3. **Output handling options**:
   - **Inline**: Insert output below code block
   - **Float**: Show in floating window
   - **Virtual text**: Show as virtual text
   - **Replace**: Replace block with output

4. **Output format** (inline mode):
   ````markdown
   ```bash
   echo "Hello, World!"
   ```

   ```output
   Hello, World!
   ```
   ````

5. **Language runners**:
   ```lua
   local runners = {
     bash = function(code) return vim.fn.system(code) end,
     sh = function(code) return vim.fn.system(code) end,
     lua = function(code) return loadstring(code)() end,
     python = function(code) return vim.fn.system("python3 -c " .. vim.fn.shellescape(code)) end,
   }
   ```

6. **Safety features**:
   - Confirmation for destructive commands
   - Timeout for long-running code
   - Sandboxing options

7. **Configuration**:
   ```lua
   require("womwiki").setup({
     codeblocks = {
       output_mode = "inline",    -- "inline", "float", "virtual"
       timeout = 10000,           -- ms
       runners = {
         rust = function(code)
           -- custom runner
         end,
       },
     },
   })
   ```

**Dependencies**: None

---

## Stage 11: Export to HTML/PDF

**Summary**: Export wiki notes to HTML or PDF for sharing outside Neovim.

**Motivation**: Not everyone uses Neovim. Sharing documentation with teammates, publishing to a wiki, or creating printable docs requires export. Pandoc integration handles most formats.

**Implementation**:

1. **Commands**:
   - `:WomExport html` – Export current file to HTML
   - `:WomExport pdf` – Export current file to PDF
   - `:WomExportAll html` – Export entire wiki to HTML site

2. **Export backends**:
   - **Pandoc** (recommended): Handles most formats
   - **Native**: Basic HTML generation without dependencies

3. **Output locations**:
   - Single file: `<wiki>/_export/<filename>.html`
   - Full wiki: `<wiki>/_site/` (gitignored)

4. **Pandoc integration**:
   ```lua
   local function export_pandoc(filepath, format)
     local output = filepath:gsub("%.md$", "." .. format)
     local cmd = string.format(
       "pandoc %s -o %s --standalone",
       vim.fn.shellescape(filepath),
       vim.fn.shellescape(output)
     )
     vim.fn.system(cmd)
     return output
   end
   ```

5. **Wiki link resolution**:
   - Convert `[text](file.md)` → `[text](file.html)` for HTML export
   - Convert `[[wikilinks]]` to proper HTML links
   - Handle relative paths

6. **Styling**:
   - Default CSS for HTML exports
   - Custom CSS via config or wiki file
   - Code syntax highlighting

7. **Static site generation** (advanced):
   - Generate `index.html` with file listing
   - Preserve directory structure
   - Include backlinks on each page

8. **Configuration**:
   ```lua
   require("womwiki").setup({
     export = {
       backend = "pandoc",        -- or "native"
       output_dir = "_export",
       html_css = nil,            -- path to custom CSS
       pdf_engine = "pdflatex",   -- or "wkhtmltopdf"
     },
   })
   ```

**External dependencies**: 
- Pandoc (for full functionality)
- LaTeX or wkhtmltopdf (for PDF)

---

## Implementation Notes

### Priority Suggestions

| Priority | Stage | Rationale |
|----------|-------|-----------|
| High | Stage 1 | Docs are foundational, enable discoverability |
| High | Stage 2 | Quick capture is low-effort, high-impact |
| High | Stage 3 | Templates leverage existing daily template system |
| Medium | Stage 4 | Improves linking UX significantly |
| Medium | Stage 7 | Essential for wiki maintenance |
| Medium | Stage 6 | Tags scale wiki organization |
| Low | Stage 5 | Nice-to-have, markdown links work fine |
| Low | Stage 8 | Useful but niche workflow |
| Low | Stage 9 | Helpful for large wikis |
| Low | Stage 10 | Advanced feature, many external tools exist |
| Low | Stage 11 | Pandoc already works, this is convenience |

### Architecture Recommendations

Before implementing multiple stages, consider:

1. **Modularize init.lua**: Split into `calendar.lua`, `graph.lua`, `menu.lua`, `templates.lua`
2. **Add LuaLS annotations**: Enable IDE support and catch bugs early
3. **Expand test coverage**: Each stage should have tests

### Testing Each Stage

Each stage should include:
- Unit tests for core functions
- Integration tests for commands
- Edge cases (empty wiki, missing files, special characters)

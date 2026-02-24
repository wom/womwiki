# Changelog

Notable changes to womwiki are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Index file support (open wiki root index.md)
- Custom todo markers and statuses
- Task filtering and sorting options

## [0.0.2] - 2026-02-23

### Added
- **Todo auto-rollover**: Incomplete todos from the most recent previous daily note are automatically copied to newly created daily notes
  - Maintains todo state across days (`[ ]` unchecked, `[-]` in-progress)
  - Adds visible rollover section with link back to source date: `## Rolled over from [[2026-02-23]]`
  - Marks forwarded todos in source file with `[>]` to indicate they've been carried forward
  - Skips gaps: pulls from last actual daily note, not just yesterday
- **Smart split behavior**: Daily notes open contextually
  - Splits when actively editing a file (top 20% of window, minimum 10 lines)
  - Full screen when on splash screen or empty buffer (no active editing)
- **Inbox elevated to top-level menu**: Quick capture now accessible directly from main menu (leader-w-i) instead of nested in Tools

### Fixed
- Todo extraction regex patterns now properly match `[ ]` and `[-]` checkboxes
- Todo forwarding logic simplified to handle whitespace variations robustly
- Removed duplicate version field from config module (kept only in init.lua as source of truth)

### Changed
- Improved context awareness for daily note opening behavior
- Enhanced menu structure: Inbox moved from Tools submenu to main menu for faster access

## [0.0.1] - 2026-02-01

### Added
- Initial release
- Daily note management: create, open, navigate between dates
- Quick capture system with optional location links
- Wiki file browser and search
- Calendar view integration
- Wikilink support with intelligent link following
- Tag system: inline tags, frontmatter support, filtering by tag
- Backlinks and graph visualization
- Daily note template customization
- Cleanup utility for unmodified daily notes
- Header modernization for daily navigation links
- Multi-picker support: Telescope, Mini.pick, FZF, Snacks
- Link autocompletion with file and heading suggestions
- Markdown checkbox toggling (leader-mc)

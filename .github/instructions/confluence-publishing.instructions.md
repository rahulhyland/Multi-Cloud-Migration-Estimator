---
name: confluence-publishing
description: "Use when publishing migration reports to Atlassian Confluence via MCP tools. Provides tool sequence, page creation, update flow, and validation checks."
applyTo: "Reports/**/*.md"
---

# Confluence Publishing Helper

## Quick Reference

When publishing a migration report to Confluence from the `Reports/` folder:

1. **Locate target space** — use `confluence_list_spaces` (or `confluence_search`) and select key from `ATLASSIAN_SPACE_KEY`.
2. **Check for existing page title** — use `confluence_search` with CQL.
3. **Create or update page** — use `confluence_create_page` or `confluence_update_page`.
4. **Verify final content** — use `confluence_get_page`.

## MCP Tool Sequence

### 1. Find space

- Tool: `confluence_list_spaces`
- Goal: find configured space key from `ATLASSIAN_SPACE_KEY` and capture `spaceId`.

### 2. Search by title

- Tool: `confluence_search`
- CQL example: `type=page AND space="${ATLASSIAN_SPACE_KEY}" AND title="Migration Report - 2026-04-14 15:30 UTC"`
- If found, capture `pageId` and current `version`.

### 3A. Create page

- Tool: `confluence_create_page`
- Params:
  - `spaceId`
  - `title`
  - `body` (storage-compatible content)

### 3B. Update page

- Tool: `confluence_update_page`
- Params:
  - `pageId`
  - `title`
  - `body`
  - `version` (must be current + 1)

### 4. Validate and return URL

- Tool: `confluence_get_page`
- Return page ID and final URL to user.

## Error Codes & Handling

| Scenario          | Meaning                              | Action                                                        |
| ----------------- | ------------------------------------ | ------------------------------------------------------------- |
| Auth failure      | Invalid email/token or wrong domain  | Verify `.env` values and restart MCP server                   |
| Permission denied | Missing write access in target space | Validate Confluence permissions                               |
| Version conflict  | Stale version on update              | Re-fetch with `confluence_get_page`, increment version, retry |
| Title collision   | Page already exists                  | Switch to update flow                                         |

## Markdown to Confluence Conversion

MCP page APIs generally expect storage-compatible content. Keep report conversion simple:

- Convert markdown headings, lists, tables, and code blocks to storage-safe HTML.
- Keep Mermaid blocks as fenced code if native rendering is unavailable.
- Validate final body by reading back with `confluence_get_page`.

## Implementation Pattern

1. Read newest report from `Reports/multi-cloud-migration-report-*.md`.
2. Build page title from report timestamp.
3. Resolve `spaceId` for `ATLASSIAN_SPACE_KEY` using `confluence_list_spaces`.
4. Search existing page with `confluence_search`.
5. If not found, call `confluence_create_page`.
6. If found, call `confluence_get_page`, then `confluence_update_page` with incremented version.
7. Confirm page ID + URL and local report path.

## Security Notes

- **API tokens in `.env`**: Never commit `.env` to git (it's in `.gitignore`)
- **Token scope**: Ensure token has Confluence read/write permissions
- **Space access**: `ATLASSIAN_SPACE_KEY` must refer to a writable team/shared space for publishing
- **Credentials in logs**: Do not print token values or decoded secrets

## Testing Checklist

After implementing Confluence publishing:

1. Agent can access Atlassian MCP tools.
2. `confluence_list_spaces` returns the configured `ATLASSIAN_SPACE_KEY`.
3. `confluence_create_page` succeeds for a new title.
4. `confluence_update_page` succeeds for an existing title.
5. `confluence_get_page` returns expected content.
6. Agent confirms page URL and local report path.

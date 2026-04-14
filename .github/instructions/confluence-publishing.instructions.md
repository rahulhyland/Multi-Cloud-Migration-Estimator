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
4. **Upload SVG attachments** — upload each `.svg` file from the report subfolder to the page.
5. **Verify final content** — use `confluence_get_page`.

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
  - `body` (Confluence storage HTML — headings, tables, lists, `<ac:image>` for SVG attachments)

### 3B. Update page

- Tool: `confluence_update_page`
- Params:
  - `pageId`
  - `title`
  - `body`
  - `version` (must be current + 1)

### 3C. Upload SVG attachments

After page is created or updated, upload each SVG diagram file from the report subfolder:
- Endpoint: `POST /wiki/rest/api/content/{pageId}/child/attachment`
- Header: `X-Atlassian-Token: no-check` (required to bypass XSRF protection)
- Form field: `file=@<path>.svg;type=image/svg+xml`
- SVG files reside alongside the report in `Reports/<timestamp>/`
- One upload per file: `*-aws-source.svg`, `*-azure-target.svg`, `*-gcp-target.svg`

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
| Attachment 403    | XSRF check blocked upload            | Ensure `X-Atlassian-Token: no-check` header is present        |

## Markdown to Confluence Conversion

Reports embed draw.io SVG diagrams (not Mermaid). Use Confluence storage HTML for the full body:

- Convert markdown headings (`#`–`######`) to `<h1>`–`<h6>`.
- Convert markdown tables to `<table><tbody>` with `<th>` for header rows.
- Convert bullet and numbered lists to `<ul>`/`<ol>` with nested-indent support.
- Convert bold/italic/inline-code to `<strong>`/`<em>`/`<code>`.
- Convert draw.io SVG image references (`![alt](file.svg)`) to Confluence attachment syntax:
  ```xml
  <ac:image ac:alt="Alt text"><ri:attachment ri:filename="file.svg" /></ac:image>
  ```
  SVG files must be uploaded as page attachments (step 3C) so the inline references resolve.
- Convert fenced code blocks to `<ac:structured-macro ac:name="code">` with `<ac:plain-text-body><![CDATA[...]]></ac:plain-text-body>`.
- Do **not** wrap the full report in `<pre><code>` — this breaks table rendering and SVG display.
- Validate final body by reading back with `confluence_get_page`.

## Implementation Pattern

1. Find the newest report: `Reports/<timestamp>/multi-cloud-migration-report-*.md` (reports live in timestamped subfolders).
2. Build page title from the report filename timestamp.
3. Convert the markdown report to Confluence storage HTML (headings, tables, lists, `<ac:image>` for SVG references).
4. Resolve `spaceId` for `ATLASSIAN_SPACE_KEY` using `confluence_list_spaces`.
5. Search existing page with `confluence_search`.
6. If not found, call `confluence_create_page` with converted body.
7. If found, call `confluence_get_page`, then `confluence_update_page` with incremented version and converted body.
8. Upload each `.svg` file from the report subfolder as a page attachment.
9. Confirm page ID + URL and local report path.

## Security Notes

- **API tokens in `.env`**: Never commit `.env` to git (it's in `.gitignore`)
- **Token scope**: Ensure token has Confluence read/write permissions
- **Space access**: `ATLASSIAN_SPACE_KEY` must refer to a writable team/shared space for publishing
- **Credentials in logs**: Do not print token values or decoded secrets

## Testing Checklist

After implementing Confluence publishing:

1. Agent can access Atlassian MCP tools.
2. `confluence_list_spaces` returns the configured `ATLASSIAN_SPACE_KEY`.
3. Report discovered from `Reports/<timestamp>/` subfolder, not flat `Reports/`.
4. `confluence_create_page` succeeds for a new title.
5. `confluence_update_page` succeeds for an existing title.
6. SVG attachments uploaded and `<ac:image>` references resolve in page body.
7. `confluence_get_page` returns expected content with diagrams visible.
8. Agent confirms page URL, page ID, and local report path.

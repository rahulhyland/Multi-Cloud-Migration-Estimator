#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$REPO_ROOT/Reports"
ENV_FILE="$REPO_ROOT/.env"
SPACE_KEY=""

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [ -z "${ATLASSIAN_API_EMAIL:-}" ] || [ -z "${ATLASSIAN_API_TOKEN:-}" ] || [ -z "${ATLASSIAN_API_ENDPOINT:-}" ]; then
  echo "ERROR: Missing Atlassian credentials in .env"
  exit 1
fi

SPACE_KEY="${ATLASSIAN_SPACE_KEY:-}"
if [ -z "$SPACE_KEY" ]; then
  echo "ERROR: Missing ATLASSIAN_SPACE_KEY in .env"
  echo "Set ATLASSIAN_SPACE_KEY to a shared Confluence space key (for example, ENG), not a personal space."
  exit 1
fi

if [[ "$SPACE_KEY" == ~* ]]; then
  echo "ERROR: ATLASSIAN_SPACE_KEY must be a shared space key, not a personal space key: $SPACE_KEY"
  echo "Use a team/shared space key so published pages are visible to all Confluence users with access to that space."
  exit 1
fi

# Reports: prefer new format Reports/<timestamp>/report.md, fall back to old Reports/*/multi-cloud-migration-report-*.md
LATEST_REPORT=""
LATEST_REPORT_NEW=$(ls -dt "$REPORTS_DIR"/multi-cloud-migration-*-utc 2>/dev/null | head -1)
if [ -n "$LATEST_REPORT_NEW" ] && [ -f "$LATEST_REPORT_NEW/report.md" ]; then
  LATEST_REPORT="$LATEST_REPORT_NEW/report.md"
fi
if [ -z "$LATEST_REPORT" ]; then
  LATEST_REPORT=$(ls -t "$REPORTS_DIR"/*/multi-cloud-migration-report-*.md 2>/dev/null | head -1)
fi
if [ -z "$LATEST_REPORT" ]; then
  echo "ERROR: No migration reports found in $REPORTS_DIR"
  echo "Expected: $REPORTS_DIR/multi-cloud-migration-<timestamp>-utc/report.md"
  exit 1
fi

REPORT_DIR="$(dirname "$LATEST_REPORT")"
echo "Found latest report: $(basename "$LATEST_REPORT") in $(basename "$REPORT_DIR")"
echo "Report folder:       $(basename "$REPORT_DIR")"

REPORT_TITLE=$(python3 - "$LATEST_REPORT" "$REPORT_DIR" <<'PY'
import pathlib
import re
import sys

report_path = pathlib.Path(sys.argv[1])
report_dir  = pathlib.Path(sys.argv[2])

# New format: folder is multi-cloud-migration-YYYYMMDD-HHMMSS-utc
folder_match = re.match(r"multi-cloud-migration-(\d{8})-(\d{6})-utc$", report_dir.name)
if folder_match:
    date_part, time_part = folder_match.groups()
    print(
        f"Migration Report - {date_part[:4]}-{date_part[4:6]}-{date_part[6:8]} "
        f"{time_part[:2]}:{time_part[2:4]} UTC"
    )
    sys.exit(0)

# Old format: filename is multi-cloud-migration-report-YYYYMMDD-HHMMSS-utc.md
name_match = re.match(r"multi-cloud-migration-report-(\d{8})-(\d{6})-utc\.md$", report_path.name)
if name_match:
    date_part, time_part = name_match.groups()
    print(
        f"Migration Report - {date_part[:4]}-{date_part[4:6]}-{date_part[6:8]} "
        f"{time_part[:2]}:{time_part[2:4]} UTC"
    )
    sys.exit(0)

raise SystemExit(f"Cannot derive title from: {report_path}")
PY
)

echo "Report title: $REPORT_TITLE"
echo "Target space: $SPACE_KEY"

# Temp files for body HTML and JSON payload (avoids shell argument-length limits)
BODY_TMPFILE=$(mktemp /tmp/confluence-body-XXXXXX.html)
PAYLOAD_TMPFILE=$(mktemp /tmp/confluence-payload-XXXXXX.json)
trap 'rm -f "$BODY_TMPFILE" "$PAYLOAD_TMPFILE"' EXIT

# Convert markdown to Confluence storage HTML.
# SVG image references (draw.io exports) become <ac:image> attachment references.
python3 - "$LATEST_REPORT" > "$BODY_TMPFILE" <<'PY'
import html as htmllib
import pathlib
import re
import sys


def inline_fmt(text):
    text = re.sub(r'\*\*\*(.+?)\*\*\*', r'<strong><em>\1</em></strong>', text)
    text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'\*(.+?)\*', r'<em>\1</em>', text)
    text = re.sub(r'`([^`]+)`', lambda m: '<code>' + htmllib.escape(m.group(1)) + '</code>', text)
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
    return text


def convert_table(rows):
    parsed_rows = []
    for row in rows:
        s = row.strip()
        if re.match(r'^\|[-: |]+\|$', s):
            continue
        parsed_rows.append([c.strip() for c in s.strip('|').split('|')])

    if not parsed_rows:
        return ''

    col_count = max(len(r) for r in parsed_rows)
    col_weights = [1] * col_count
    for r in parsed_rows:
        for idx in range(col_count):
            cell_len = len(r[idx]) if idx < len(r) else 0
            col_weights[idx] = max(col_weights[idx], min(cell_len, 80))

    total_weight = sum(col_weights) or 1
    # Use softer bounds so wide tables with many columns stay readable.
    min_col = 3
    max_col = 45
    widths = [max(min_col, min(max_col, int(round((w / total_weight) * 100)))) for w in col_weights]

    # Rebalance widths to total ~100 while honoring bounds.
    delta = 100 - sum(widths)
    step = 1 if delta > 0 else -1
    i = 0
    while delta != 0 and i < 500:
        idx = i % len(widths)
        candidate = widths[idx] + step
        if min_col <= candidate <= max_col:
            widths[idx] = candidate
            delta -= step
        i += 1

    out = ['<table data-layout="default" style="table-layout:auto;width:100%;"><colgroup>']
    for width in widths:
        out.append(f'<col style="width:{width}%;" />')
    out.append('</colgroup><tbody>')

    out.append('<tr>' + ''.join(
        f'<th style="white-space:normal;"><p>{inline_fmt(parsed_rows[0][i] if i < len(parsed_rows[0]) else "")}</p></th>'
        for i in range(col_count)
    ) + '</tr>')

    for row in parsed_rows[1:]:
        out.append('<tr>' + ''.join(
            f'<td style="white-space:normal;word-break:break-word;"><p>{inline_fmt(row[i] if i < len(row) else "")}</p></td>'
            for i in range(col_count)
        ) + '</tr>')

    out.append('</tbody></table>')
    return '\n'.join(out)


def build_list_html(items):
    """Build nested list HTML from [(indent, is_ordered, text)]."""
    if not items:
        return ''
    out = []
    stack = []  # (indent, tag)
    for indent, is_ordered, text in items:
        tag = 'ol' if is_ordered else 'ul'
        if not stack:
            out.append(f'<{tag}>')
            stack.append((indent, tag))
        elif indent > stack[-1][0]:
            out.append(f'<{tag}>')
            stack.append((indent, tag))
        elif indent < stack[-1][0]:
            while stack and stack[-1][0] > indent:
                out.append(f'</{stack.pop()[1]}>')
            if not stack or stack[-1][0] < indent:
                out.append(f'<{tag}>')
                stack.append((indent, tag))
        out.append(f'<li><p>{inline_fmt(text)}</p></li>')
    while stack:
        out.append(f'</{stack.pop()[1]}>')
    return '\n'.join(out)


def convert(content):
    lines = content.split('\n')
    result = []
    i = 0
    table_buf = []
    in_code = False
    code_lang = ''
    code_buf = []
    list_items = []  # (indent, is_ordered, text)

    def flush_table():
        if table_buf:
            result.append(convert_table(list(table_buf)))
            table_buf.clear()

    def flush_list():
        if list_items:
            result.append(build_list_html(list(list_items)))
            list_items.clear()

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Code fence
        fence_m = re.match(r'^```(\w*)$', stripped)
        if fence_m and not in_code:
            flush_table()
            flush_list()
            code_lang = fence_m.group(1) or ''
            in_code = True
            code_buf = []
            i += 1
            continue

        if in_code:
            if stripped == '```':
                lang_param = (
                    f'<ac:parameter ac:name="language">{htmllib.escape(code_lang)}</ac:parameter>'
                    if code_lang else ''
                )
                raw = '\n'.join(code_buf).replace(']]>', ']]]]><![CDATA[>')
                result.append(
                    f'<ac:structured-macro ac:name="code">{lang_param}'
                    f'<ac:plain-text-body><![CDATA[{raw}]]></ac:plain-text-body>'
                    f'</ac:structured-macro>'
                )
                in_code = False
                code_buf = []
            else:
                code_buf.append(line)
            i += 1
            continue

        # Table rows
        if stripped.startswith('|'):
            flush_list()
            table_buf.append(line)
            i += 1
            continue
        else:
            flush_table()

        # Heading
        heading_m = re.match(r'^(#{1,6})\s+(.+)$', line)
        if heading_m:
            flush_list()
            level = len(heading_m.group(1))
            result.append(f'<h{level}>{inline_fmt(heading_m.group(2))}</h{level}>')
            i += 1
            continue

        # Image — draw.io SVG embedded as Confluence attachment reference
        img_m = re.match(r'^!\[([^\]]*)\]\(([^)]+)\)$', stripped)
        if img_m:
            flush_list()
            filename = img_m.group(2)
            alt = img_m.group(1)
            if filename.startswith('http://') or filename.startswith('https://'):
                result.append(f'<p><img src="{htmllib.escape(filename)}" alt="{htmllib.escape(alt)}" /></p>')
            else:
                result.append(
                    '<p style="overflow-x:auto;max-width:100%;">'
                  f'<ac:image ac:alt="{htmllib.escape(alt)}" ac:width="900">'
                    f'<ri:attachment ri:filename="{htmllib.escape(filename)}" />'
                    f'</ac:image></p>'
                )
            i += 1
            continue

        # Unordered list item
        ul_m = re.match(r'^(\s*)[-*+]\s+(.+)$', line)
        if ul_m:
            indent = len(ul_m.group(1))
            list_items.append((indent, False, ul_m.group(2)))
            i += 1
            continue

        # Ordered list item
        ol_m = re.match(r'^(\s*)\d+\.\s+(.+)$', line)
        if ol_m:
            indent = len(ol_m.group(1))
            list_items.append((indent, True, ol_m.group(2)))
            i += 1
            continue

        flush_list()

        # Horizontal rule
        if re.match(r'^[-*_]{3,}$', stripped):
            result.append('<hr />')
            i += 1
            continue

        # Empty line
        if stripped == '':
            result.append('')
            i += 1
            continue

        # Regular paragraph
        result.append(f'<p>{inline_fmt(line)}</p>')
        i += 1

    flush_table()
    flush_list()
    return '\n'.join(result)


content = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
print(convert(content))
PY

echo ""
echo "Step 1: Validating Confluence space..."
SPACE_LOOKUP=$(curl -sS -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
  "$ATLASSIAN_API_ENDPOINT/wiki/api/v2/spaces?keys=$SPACE_KEY" \
  -H "Accept: application/json")

SPACE_ID=$(echo "$SPACE_LOOKUP" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data['results'][0]['id'] if data.get('results') else '')" 2>/dev/null || true)
if [ -z "$SPACE_ID" ]; then
  echo "ERROR: Could not resolve space $SPACE_KEY"
  echo "$SPACE_LOOKUP"
  exit 1
fi

echo "✓ Space ID: $SPACE_ID"

echo ""
echo "Step 2: Searching for an existing page..."
SEARCH_CQL=$(python3 - "$SPACE_KEY" "$REPORT_TITLE" <<'PY'
import sys
import urllib.parse

space_key, title = sys.argv[1:3]
cql = f'type=page AND space="{space_key}" AND title="{title}"'
print(urllib.parse.quote(cql))
PY
)
SEARCH_RESULT=$(curl -sS -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
  "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/search?cql=$SEARCH_CQL&limit=1" \
  -H "Accept: application/json")

EXISTING_PAGE_ID=$(echo "$SEARCH_RESULT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data['results'][0]['id'] if data.get('results') else '')" 2>/dev/null || true)

if [ -z "$EXISTING_PAGE_ID" ]; then
  echo "✓ No existing page found. Creating a new page..."
  python3 - "$SPACE_KEY" "$REPORT_TITLE" "$BODY_TMPFILE" "$PAYLOAD_TMPFILE" <<'PY'
import json
import pathlib
import sys

space_key, title, body_file, payload_file = sys.argv[1:5]
body_value = pathlib.Path(body_file).read_text(encoding='utf-8')
payload = {
    "type": "page",
    "title": title,
    "space": {"key": space_key},
    "body": {"storage": {"value": body_value, "representation": "storage"}}
}
pathlib.Path(payload_file).write_text(json.dumps(payload), encoding='utf-8')
PY
  CREATE_RESPONSE=$(curl -sS -w "\n%{http_code}" -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X POST "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    --data-binary "@$PAYLOAD_TMPFILE")
  HTTP_STATUS=$(echo "$CREATE_RESPONSE" | tail -1)
  RESPONSE_BODY=$(echo "$CREATE_RESPONSE" | sed '$d')
  if [ "$HTTP_STATUS" != "200" ]; then
    echo "ERROR: Failed to create page (HTTP $HTTP_STATUS)"
    echo "$RESPONSE_BODY"
    exit 1
  fi
  PAGE_ID=$(echo "$RESPONSE_BODY" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data['id'])")
else
  echo "✓ Found existing page: $EXISTING_PAGE_ID"
  PAGE_INFO=$(curl -sS -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$EXISTING_PAGE_ID?expand=version" \
    -H "Accept: application/json")
  CURRENT_VERSION=$(echo "$PAGE_INFO" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data['version']['number'])")
  NEXT_VERSION=$((CURRENT_VERSION + 1))
  python3 - "$EXISTING_PAGE_ID" "$SPACE_KEY" "$REPORT_TITLE" "$BODY_TMPFILE" "$NEXT_VERSION" "$PAYLOAD_TMPFILE" <<'PY'
import json
import pathlib
import sys

page_id, space_key, title, body_file, version, payload_file = sys.argv[1:7]
body_value = pathlib.Path(body_file).read_text(encoding='utf-8')
payload = {
    "id": page_id,
    "type": "page",
    "title": title,
    "space": {"key": space_key},
    "body": {"storage": {"value": body_value, "representation": "storage"}},
    "version": {"number": int(version)}
}
pathlib.Path(payload_file).write_text(json.dumps(payload), encoding='utf-8')
PY
  UPDATE_RESPONSE=$(curl -sS -w "\n%{http_code}" -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X PUT "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$EXISTING_PAGE_ID" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    --data-binary "@$PAYLOAD_TMPFILE")
  HTTP_STATUS=$(echo "$UPDATE_RESPONSE" | tail -1)
  RESPONSE_BODY=$(echo "$UPDATE_RESPONSE" | sed '$d')
  if [ "$HTTP_STATUS" != "200" ]; then
    echo "ERROR: Failed to update page (HTTP $HTTP_STATUS)"
    echo "$RESPONSE_BODY"
    exit 1
  fi
  PAGE_ID="$EXISTING_PAGE_ID"
fi

echo ""
echo "Step 3: Uploading SVG diagram attachments..."
SVG_UPLOADED=0
set +e
for SVG_FILE in "$REPORT_DIR"/*.svg; do
  [ -f "$SVG_FILE" ] || continue
  SVG_NAME="$(basename "$SVG_FILE")"
  echo "  Uploading: $SVG_NAME"
  ATTACH_RESPONSE=$(curl -sS -w "\n%{http_code}" \
    -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X POST "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID/child/attachment" \
    -H "Accept: application/json" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${SVG_FILE};type=image/svg+xml" \
    -F "comment=Architecture diagram" 2>/dev/null)
  ATTACH_STATUS=$(echo "$ATTACH_RESPONSE" | tail -1)
  if [ "$ATTACH_STATUS" = "200" ] || [ "$ATTACH_STATUS" = "201" ]; then
    echo "  ✓ Uploaded $SVG_NAME"
    SVG_UPLOADED=$((SVG_UPLOADED + 1))
  else
    echo "  WARNING: Failed to upload $SVG_NAME (HTTP $ATTACH_STATUS)"
  fi
done
set -e
if [ "$SVG_UPLOADED" -eq 0 ]; then
  echo "  No SVG files found in $(basename "$REPORT_DIR") (diagrams will not render inline)"
else
  echo "  Uploaded $SVG_UPLOADED SVG file(s)"
fi

echo ""
echo "Step 4: Verifying published page..."
PAGE_DETAILS=$(curl -sS -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
  "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID" \
  -H "Accept: application/json")
PAGE_WEBUI=$(echo "$PAGE_DETAILS" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('_links', {}).get('webui', ''))")
PAGE_URL="$ATLASSIAN_API_ENDPOINT/wiki${PAGE_WEBUI}"

echo ""
echo "================================"
echo "SUCCESS"
echo "================================"
echo "Title:    $REPORT_TITLE"
echo "Page ID:  $PAGE_ID"
echo "Local:    $(basename "$LATEST_REPORT")"
echo "Diagrams: $SVG_UPLOADED SVG attachment(s) uploaded"
echo "URL:      $PAGE_URL"

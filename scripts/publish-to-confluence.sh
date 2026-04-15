#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$REPO_ROOT/Reports"
ENV_FILE="$REPO_ROOT/.env"
SPACE_KEY=""
DRY_RUN=0
DRY_RUN_SAVE_BODY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --dry-run-save-body)
      DRY_RUN=1
      DRY_RUN_SAVE_BODY=1
      ;;
    *)
      echo "ERROR: Unknown argument: $arg"
      echo "Usage: $0 [--dry-run] [--dry-run-save-body]"
      exit 1
      ;;
  esac
done

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

# Reports are stored in timestamped subfolders: Reports/*-YYYYMMDD-HHMMSS-utc/
# Select the latest report deterministically from folder timestamp tokens.
LATEST_REPORT=$(python3 - "$REPORTS_DIR" <<'PY'
import pathlib
import re
import sys

reports_dir = pathlib.Path(sys.argv[1])
folder_re = re.compile(r'^.+-(\d{8})-(\d{6})-utc$')
latest = None

for child in reports_dir.iterdir():
  if not child.is_dir():
    continue
  match = folder_re.match(child.name)
  if not match:
    continue

  report_files = sorted(child.glob('multi-cloud-migration-report-*.md'))
  if not report_files:
    continue
  if len(report_files) > 1:
    print(
      f"ERROR: Multiple report markdown files found in {child}: "
      + ', '.join(f.name for f in report_files),
      file=sys.stderr,
    )
    sys.exit(2)

  timestamp_key = (match.group(1), match.group(2))
  current = (timestamp_key, str(report_files[0]))
  if latest is None or current[0] > latest[0]:
    latest = current

if latest is None:
  print(
    f"ERROR: No migration reports found in timestamped subdirectories under {reports_dir}",
    file=sys.stderr,
  )
  print(
    "Expected: Reports/*-YYYYMMDD-HHMMSS-utc/multi-cloud-migration-report-*.md",
    file=sys.stderr,
  )
  sys.exit(1)

print(latest[1])
PY
)

REPORT_DIR="$(dirname "$LATEST_REPORT")"
SOURCE_FOLDER_NAME="$(basename "$REPORT_DIR")"
echo "Found latest report: $(basename "$LATEST_REPORT")"
echo "Report folder:       $(basename "$REPORT_DIR")"

REPORT_TITLE="$SOURCE_FOLDER_NAME"

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

    # Keep wide tables readable: make total width larger than page width and rely on horizontal scroll.
    table_min_width = max(1400, col_count * 220)
    min_col_px = 160
    max_col_px = 520
    widths = [
        max(min_col_px, min(max_col_px, int(round((w / total_weight) * table_min_width))))
        for w in col_weights
    ]

    out = [
        f'<div style="overflow-x:auto;max-width:100%;"><table data-layout="default" '
        f'style="table-layout:auto;width:max-content;min-width:{table_min_width}px;"><colgroup>'
    ]
    for width in widths:
        out.append(f'<col style="width:{width}px;" />')
    out.append('</colgroup><tbody>')

    th_style = 'white-space:normal;word-break:normal;overflow-wrap:anywhere;padding:10px 14px;line-height:1.45;vertical-align:top;'
    td_style = 'white-space:normal;word-break:normal;overflow-wrap:anywhere;padding:10px 14px;line-height:1.45;vertical-align:top;'

    def table_cell_fmt(text):
        return inline_fmt(text).replace('\n', '<br />')

    out.append('<tr>' + ''.join(
        f'<th style="{th_style}">{table_cell_fmt(parsed_rows[0][i] if i < len(parsed_rows[0]) else "")}</th>'
        for i in range(col_count)
    ) + '</tr>')

    for row in parsed_rows[1:]:
        out.append('<tr>' + ''.join(
            f'<td style="{td_style}">{table_cell_fmt(row[i] if i < len(row) else "")}</td>'
            for i in range(col_count)
        ) + '</tr>')

    out.append('</tbody></table></div>')
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


def convert(content, report_dir):
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

        # Image handling:
        # - External URLs stay as regular images.
        # - Local .svg refs render inline via Confluence attachments.
        # - If a sibling .drawio file exists, add a source-file link below the image.
        img_m = re.match(r'^!\[([^\]]*)\]\(([^)]+)\)$', stripped)
        if img_m:
            flush_list()
            filename = img_m.group(2).strip()
            alt = img_m.group(1)
            if filename.startswith('http://') or filename.startswith('https://'):
                result.append(f'<p><img src="{htmllib.escape(filename)}" alt="{htmllib.escape(alt)}" /></p>')
            elif filename.lower().endswith('.svg'):
                drawio_filename = re.sub(r'\.svg$', '.drawio', filename, flags=re.IGNORECASE)
                drawio_path = report_dir / drawio_filename
                result.append(
                    '<p style="overflow-x:auto;max-width:100%;">'
                    f'<ac:image ac:alt="{htmllib.escape(alt)}" ac:width="1100">'
                    f'<ri:attachment ri:filename="{htmllib.escape(filename)}" />'
                    f'</ac:image></p>'
                )
                if drawio_path.exists():
                    link_body = (alt.strip() or pathlib.Path(drawio_filename).name) + ' (drawio source)'
                    link_body = link_body.replace(']]>', ']]]]><![CDATA[>')
                    result.append(
                        '<p>'
                        f'<ac:link><ri:attachment ri:filename="{htmllib.escape(drawio_filename)}" />'
                        f'<ac:plain-text-link-body><![CDATA[{link_body}]]></ac:plain-text-link-body>'
                        '</ac:link>'
                        '</p>'
                    )
                else:
                    result.append(
                        '<p><strong>Warning:</strong> '
                        f'Missing drawio source for diagram reference: '
                        f'<code>{htmllib.escape(drawio_filename)}</code></p>'
                    )
            else:
                result.append(
                    '<p style="overflow-x:auto;max-width:100%;">'
                    f'<ac:image ac:alt="{htmllib.escape(alt)}" ac:width="1100">'
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


report_file = pathlib.Path(sys.argv[1])
content = report_file.read_text(encoding='utf-8')
print(convert(content, report_file.parent))
PY

if [ "$DRY_RUN" -eq 1 ]; then
  DRY_RUN_BODY_OUTFILE="$REPORT_DIR/confluence-body-preview.html"
  if [ "$DRY_RUN_SAVE_BODY" -eq 1 ]; then
    cp "$BODY_TMPFILE" "$DRY_RUN_BODY_OUTFILE"
  fi

  echo ""
  echo "DRY RUN MODE: Skipping Confluence API calls and attachment uploads"
  echo "Selected report folder: $SOURCE_FOLDER_NAME"
  echo "Selected report file:   $(basename "$LATEST_REPORT")"
  echo "Resolved page title:    $REPORT_TITLE"
  echo "Generated body file:    $BODY_TMPFILE"
  if [ "$DRY_RUN_SAVE_BODY" -eq 1 ]; then
    echo "Saved body preview:     $DRY_RUN_BODY_OUTFILE"
  fi

  python3 - "$BODY_TMPFILE" "$REPORT_DIR" <<'PY'
import pathlib
import re
import sys

body_path = pathlib.Path(sys.argv[1])
report_dir = pathlib.Path(sys.argv[2])
body = body_path.read_text(encoding='utf-8')

drawio_files = sorted(p.name for p in report_dir.glob('*.drawio'))
attachment_refs = sorted(set(re.findall(r'ri:filename="([^"]+)"', body)))
warning_count = len(re.findall(r'<strong>Warning:</strong>', body))

print(f"Body size (chars):      {len(body)}")
print(f"Body line count:        {body.count(chr(10)) + 1}")
print(f"Drawio files in folder: {len(drawio_files)}")
print(f"Attachment refs in body:{len(attachment_refs)}")
print(f"Inline warning blocks:  {warning_count}")

if drawio_files:
    print("Drawio files:")
    for name in drawio_files:
        print(f"  - {name}")

if attachment_refs:
    print("Referenced attachments in generated body:")
    for name in attachment_refs:
        print(f"  - {name}")

preview = '\n'.join(body.splitlines()[:20])
print("Body preview (first 20 lines):")
print(preview)
PY

  echo ""
  echo "Dry run complete. No page created or updated."
  exit 0
fi

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
echo "Step 3: Uploading diagram attachments (.drawio + .svg)..."
echo "  Note: Confluence automatically versions duplicate attachment names"

DRAWIO_FOUND=0
DRAWIO_UPLOADED=0
SVG_FOUND=0
SVG_UPLOADED=0
SVG_EXISTING=0
set +e
for DRAWIO_FILE in "$REPORT_DIR"/*.drawio; do
  [ -f "$DRAWIO_FILE" ] || continue
  DRAWIO_FOUND=$((DRAWIO_FOUND + 1))
  DRAWIO_NAME="$(basename "$DRAWIO_FILE")"
  echo "  Uploading: $DRAWIO_NAME"
  ATTACH_RESPONSE=$(curl -sS -w "\n%{http_code}" \
    -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X POST "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID/child/attachment" \
    -H "Accept: application/json" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${DRAWIO_FILE};type=application/xml" \
    -F "comment=Architecture diagram source" 2>/dev/null)
  ATTACH_STATUS=$(echo "$ATTACH_RESPONSE" | tail -1)
  ATTACH_BODY=$(echo "$ATTACH_RESPONSE" | sed '$d')
  if [ "$ATTACH_STATUS" = "200" ] || [ "$ATTACH_STATUS" = "201" ]; then
    echo "  ✓ Uploaded $DRAWIO_NAME"
    DRAWIO_UPLOADED=$((DRAWIO_UPLOADED + 1))
  elif [ "$ATTACH_STATUS" = "400" ] && echo "$ATTACH_BODY" | grep -q "same file name as an existing attachment"; then
    echo "  - Already exists: $DRAWIO_NAME"
  else
    echo "  WARNING: Failed to upload $DRAWIO_NAME (HTTP $ATTACH_STATUS)"
  fi
done

for SVG_FILE in "$REPORT_DIR"/*.svg; do
  [ -f "$SVG_FILE" ] || continue
  SVG_FOUND=$((SVG_FOUND + 1))
  SVG_NAME="$(basename "$SVG_FILE")"
  echo "  Uploading: $SVG_NAME"
  ATTACH_RESPONSE=$(curl -sS -w "\n%{http_code}" \
    -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X POST "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID/child/attachment" \
    -H "Accept: application/json" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${SVG_FILE};type=image/svg+xml" \
    -F "comment=Architecture diagram render" 2>/dev/null)
  ATTACH_STATUS=$(echo "$ATTACH_RESPONSE" | tail -1)
  ATTACH_BODY=$(echo "$ATTACH_RESPONSE" | sed '$d')
  if [ "$ATTACH_STATUS" = "200" ] || [ "$ATTACH_STATUS" = "201" ]; then
    echo "  ✓ Uploaded $SVG_NAME"
    SVG_UPLOADED=$((SVG_UPLOADED + 1))
  elif [ "$ATTACH_STATUS" = "400" ] && echo "$ATTACH_BODY" | grep -q "same file name as an existing attachment"; then
    echo "  - Already exists: $SVG_NAME"
    SVG_EXISTING=$((SVG_EXISTING + 1))
  else
    echo "  WARNING: Failed to upload $SVG_NAME (HTTP $ATTACH_STATUS)"
  fi
done
set -e
if [ "$DRAWIO_FOUND" -eq 0 ]; then
  echo "  No .drawio files found in $(basename "$REPORT_DIR")"
else
  echo "  .drawio results: uploaded=$DRAWIO_UPLOADED"
fi
if [ "$SVG_FOUND" -eq 0 ]; then
  echo "  No .svg files found in $(basename "$REPORT_DIR")"
else
  echo "  .svg results: uploaded=$SVG_UPLOADED existing=$SVG_EXISTING"
fi

echo ""
echo "Step 3b: Updating drawio links to direct download URLs..."
python3 - "$BODY_TMPFILE" "$ATLASSIAN_API_ENDPOINT" "$PAGE_ID" <<'PY'
import pathlib
import re
import sys
import urllib.parse

body_file, endpoint, page_id = sys.argv[1:4]
body = pathlib.Path(body_file).read_text(encoding='utf-8')

pattern = re.compile(
    r'<p><ac:link><ri:attachment ri:filename="([^"]+\.drawio)" />'
    r'<ac:plain-text-link-body><!\[CDATA\[(.*?)\]\]></ac:plain-text-link-body></ac:link></p>'
)

def repl(match):
    filename = match.group(1)
    label = match.group(2)
    encoded = urllib.parse.quote(filename)
    url = f"{endpoint}/wiki/download/attachments/{page_id}/{encoded}?api=v2"
    return (
        '<p>'
        f'<a href="{url}">Download {filename}</a>'
        '</p>'
    )

new_body = pattern.sub(repl, body)
pathlib.Path(body_file).write_text(new_body, encoding='utf-8')
PY

PAGE_INFO_POST_UPLOAD=$(curl -sS -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
  "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID?expand=version" \
  -H "Accept: application/json")
CURRENT_VERSION_POST_UPLOAD=$(echo "$PAGE_INFO_POST_UPLOAD" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data['version']['number'])")
NEXT_VERSION_POST_UPLOAD=$((CURRENT_VERSION_POST_UPLOAD + 1))

python3 - "$PAGE_ID" "$SPACE_KEY" "$REPORT_TITLE" "$BODY_TMPFILE" "$NEXT_VERSION_POST_UPLOAD" "$PAYLOAD_TMPFILE" <<'PY'
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

LINK_UPDATE_RESPONSE=$(curl -sS -w "\n%{http_code}" -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
  -X PUT "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data-binary "@$PAYLOAD_TMPFILE")
LINK_UPDATE_STATUS=$(echo "$LINK_UPDATE_RESPONSE" | tail -1)
LINK_UPDATE_BODY=$(echo "$LINK_UPDATE_RESPONSE" | sed '$d')
if [ "$LINK_UPDATE_STATUS" = "200" ]; then
  echo "  ✓ Drawio links updated to direct download URLs"
else
  echo "  WARNING: Could not update drawio direct links (HTTP $LINK_UPDATE_STATUS)"
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
echo "Diagrams: .drawio uploaded=$DRAWIO_UPLOADED | .svg uploaded=$SVG_UPLOADED existing=$SVG_EXISTING"
echo "URL:      $PAGE_URL"

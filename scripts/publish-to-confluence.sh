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

# Reports are stored in timestamped subfolders.
# Use Python to select the latest report by folder timestamp — skips non-timestamped folders.
LATEST_REPORT=$(python3 - "$REPORTS_DIR" <<'PY'
import pathlib
import re
import sys

reports_dir = pathlib.Path(sys.argv[1])
# Match both YYYYMMDD-HHMMSS-utc and YYYY-MM-DD-HH-MM-SS-utc folder patterns
folder_re = re.compile(
    r'^.+-(\d{8})-(\d{6})-utc$'         # YYYYMMDD-HHMMSS-utc
    r'|^.+-(\d{4}-\d{2}-\d{2})-(\d{2}-\d{2}-\d{2})-utc$'  # YYYY-MM-DD-HH-MM-SS-utc
)
candidates = []
for folder in reports_dir.iterdir():
    if not folder.is_dir():
        continue
    m = folder_re.match(folder.name)
    if not m:
        continue  # skip non-timestamped folders like Transform_Service
    # Pick report.md first, then legacy filename
    report = folder / 'report.md'
    if not report.exists():
        legacy = sorted(folder.glob('multi-cloud-migration-report-*.md'))
        report = legacy[-1] if legacy else None
    if report and report.exists():
        candidates.append((folder.name, str(report)))

if not candidates:
    print("ERROR: No migration reports found in timestamped subdirectories", file=sys.stderr)
    sys.exit(1)

# Sort by folder name (timestamp sorts lexicographically correctly)
candidates.sort(key=lambda x: x[0], reverse=True)
print(candidates[0][1])
PY
)

if [ -z "$LATEST_REPORT" ]; then
  echo "ERROR: No migration reports found in $REPORTS_DIR subdirectories"
  echo "Expected: $REPORTS_DIR/<timestamp-folder>/report.md  (or legacy multi-cloud-migration-report-*.md)"
  exit 1
fi

REPORT_DIR="$(dirname "$LATEST_REPORT")"
echo "Found latest report: $(basename "$LATEST_REPORT")"
echo "Report folder:       $(basename "$REPORT_DIR")"

REPORT_TITLE=$(python3 - "$LATEST_REPORT" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
name = path.name

# Try legacy filename: multi-cloud-migration-report-YYYYMMDD-HHMMSS-utc.md
match = re.match(r"multi-cloud-migration-report-(\d{8})-(\d{6})-utc\.md$", name)
if match:
    date_part, time_part = match.groups()
else:
    folder = path.parent.name
    # YYYYMMDD-HHMMSS-utc folder pattern
    match = re.match(r".+-(\d{8})-(\d{6})-utc$", folder)
    if match:
        date_part, time_part = match.groups()
    else:
        # YYYY-MM-DD-HH-MM-SS-utc folder pattern
        match = re.match(r".+-(\d{4}-\d{2}-\d{2})-(\d{2}-\d{2}-\d{2})-utc$", folder)
        if match:
            d, t = match.groups()
            print(f"Migration Report - {d} {t.replace('-', ':')} UTC")
            sys.exit(0)
        raise SystemExit(f"Cannot derive timestamp from filename '{name}' or folder '{folder}'")

print(
    f"Migration Report - {date_part[:4]}-{date_part[4:6]}-{date_part[6:8]} "
    f"{time_part[:2]}:{time_part[2:4]} UTC"
)
PY
)

echo "Report title: $REPORT_TITLE"
echo "Target space: $SPACE_KEY"

# Temp files for body HTML and JSON payload (avoids shell argument-length limits)
BODY_TMPFILE=$(mktemp /tmp/confluence-body-XXXXXX.html)
PAYLOAD_TMPFILE=$(mktemp /tmp/confluence-payload-XXXXXX.json)
trap 'rm -f "$BODY_TMPFILE" "$PAYLOAD_TMPFILE"' EXIT

# Convert markdown to Confluence storage HTML.
# Local SVG references are treated as draw.io sources and surfaced via draw.io macros.
python3 - "$LATEST_REPORT" > "$BODY_TMPFILE" <<'PY'
import html as htmllib
import pathlib
import re
import sys
import uuid


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

        # Image — local SVG references are published as inline draw.io macros.
        img_m = re.match(r'^!\[([^\]]*)\]\(([^)]+)\)$', stripped)
        if img_m:
          flush_list()
          filename = img_m.group(2)
          alt = img_m.group(1)
          if filename.startswith('http://') or filename.startswith('https://'):
            result.append(f'<p><img src="{htmllib.escape(filename)}" alt="{htmllib.escape(alt)}" /></p>')
          else:
            if filename.lower().endswith('.svg'):
              drawio_name = re.sub(r'\.svg$', '.drawio', filename, flags=re.IGNORECASE)
              label = htmllib.escape(alt) if alt else 'Diagram'
              macro_id = str(uuid.uuid4())
              result.append(
                '<div>'
                f'<ac:structured-macro ac:name="drawio" ac:schema-version="1" ac:macro-id="{macro_id}">'
                f'<ac:parameter ac:name="diagramName">{htmllib.escape(drawio_name)}</ac:parameter>'
                f'<ac:parameter ac:name="title">{label}</ac:parameter>'
                '</ac:structured-macro>'
                '</div>'
              )
            else:
              result.append(
                '<p><em>Referenced local image omitted in publish output. '
                'Use draw.io attachments for editable diagrams.</em></p>'
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
echo "Step 3: Normalizing draw.io files and uploading editable diagram attachments..."

DRAWIO_NORMALIZED=0
DRAWIO_TOTAL=0
set +e
for DRAWIO_FILE in "$REPORT_DIR"/*.drawio; do
  [ -f "$DRAWIO_FILE" ] || continue
  DRAWIO_TOTAL=$((DRAWIO_TOTAL + 1))
  NORMALIZE_RESULT=$(python3 - "$DRAWIO_FILE" <<'PY'
import datetime
import pathlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET

path = pathlib.Path(sys.argv[1])
content = path.read_text(encoding='utf-8')


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def wrap_in_mxfile(graph_model):
    mxfile = ET.Element('mxfile', {
        'host': 'app.diagrams.net',
        'modified': timestamp(),
        'agent': 'copilot',
        'version': '24.7.17',
        'type': 'device'
    })
    diagram = ET.SubElement(mxfile, 'diagram', {
        'id': path.stem,
        'name': path.stem
    })
    diagram.append(graph_model)
    ET.indent(mxfile, space='  ')
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(mxfile, encoding='unicode')


def extract_graph_model(root):
    if root.tag == 'mxGraphModel':
        return root
    if root.tag == 'mxfile':
        diagram = root.find('diagram')
        if diagram is None:
            raise ValueError('mxfile-missing-diagram')
        graph_model = diagram.find('mxGraphModel')
        if graph_model is None:
            raise ValueError('mxfile-missing-graphmodel')
        return graph_model
    raise ValueError(f'unexpected-root:{root.tag}')


def is_placeholder_chart(graph_model):
    for cell in graph_model.findall('.//mxCell'):
        value = cell.attrib.get('value', '')
        if 'see corresponding SVG' in value:
            return True
    return False


def has_base64_image_uri(graph_model):
    """Detect draw.io files using data:image/svg+xml;base64 — the semicolon before 'base64'
    is also draw.io's style property delimiter, causing the image URI to be truncated
    and the diagram to render blank. These must be rebuilt using URL-percent-encoding."""
    for cell in graph_model.findall('.//mxCell'):
        style = cell.attrib.get('style', '')
        if 'image=data:image/svg+xml;base64,' in style:
            return True
    return False


def parse_dimension(value):
    if not value:
        return None
    match = re.match(r'([0-9]+(?:\.[0-9]+)?)', value)
    if not match:
        return None
    return float(match.group(1))


def build_image_graph_model(svg_path):
    svg_text = svg_path.read_text(encoding='utf-8')
    svg_root = ET.fromstring(svg_text)
    width = parse_dimension(svg_root.attrib.get('width'))
    height = parse_dimension(svg_root.attrib.get('height'))

    if (width is None or height is None) and svg_root.attrib.get('viewBox'):
        parts = svg_root.attrib['viewBox'].split()
        if len(parts) == 4:
            width = width or float(parts[2])
            height = height or float(parts[3])

    width = width or 1200
    height = height or 600

    encoded_svg = urllib.parse.quote(svg_text, safe='')
    image_uri = f'data:image/svg+xml,{encoded_svg}'

    graph_model = ET.Element('mxGraphModel', {
        'dx': '1422',
        'dy': '762',
        'grid': '1',
        'gridSize': '10',
        'guides': '1',
        'tooltips': '1',
        'connect': '1',
        'arrows': '1',
        'fold': '1',
        'page': '1',
        'pageScale': '1',
        'pageWidth': str(int(width + 80)),
        'pageHeight': str(int(height + 80)),
        'math': '0',
        'shadow': '0'
    })
    root = ET.SubElement(graph_model, 'root')
    ET.SubElement(root, 'mxCell', {'id': '0'})
    ET.SubElement(root, 'mxCell', {'id': '1', 'parent': '0'})

    image_cell = ET.SubElement(root, 'mxCell', {
        'id': '2',
        'value': '',
        'style': f'shape=image;html=1;imageAspect=0;aspect=fixed;verticalLabelPosition=bottom;verticalAlign=top;image={image_uri};',
        'vertex': '1',
        'parent': '1'
    })
    ET.SubElement(image_cell, 'mxGeometry', {
        'x': '20',
        'y': '20',
        'width': str(int(width)),
        'height': str(int(height)),
        'as': 'geometry'
    })

    return graph_model


try:
    root = ET.fromstring(content.lstrip())
except Exception as exc:
    print(f'parse-error:{exc}')
    raise SystemExit(1)

try:
    graph_model = extract_graph_model(root)
except Exception as exc:
    print(str(exc))
    raise SystemExit(1)

svg_path = path.with_suffix('.svg')

needs_rebuild = (
    is_placeholder_chart(graph_model)
    or has_base64_image_uri(graph_model)
)

if needs_rebuild and svg_path.exists():
    replacement_graph_model = build_image_graph_model(svg_path)
    xml_output = wrap_in_mxfile(replacement_graph_model)
    path.write_text(xml_output, encoding='utf-8')
    print('rendered-from-svg')
    raise SystemExit(0)

if root.tag == 'mxfile':
    print('already-mxfile')
    raise SystemExit(0)

xml_output = wrap_in_mxfile(graph_model)
path.write_text(xml_output, encoding='utf-8')
print('normalized')
PY
)
  STATUS=$?
  if [ "$STATUS" -eq 0 ] && { [ "$NORMALIZE_RESULT" = "normalized" ] || [ "$NORMALIZE_RESULT" = "rendered-from-svg" ]; }; then
    if [ "$NORMALIZE_RESULT" = "rendered-from-svg" ]; then
      echo "  ✓ Rebuilt $(basename "$DRAWIO_FILE") from its SVG for draw.io rendering"
    else
      echo "  ✓ Normalized $(basename "$DRAWIO_FILE") to mxfile format"
    fi
    DRAWIO_NORMALIZED=$((DRAWIO_NORMALIZED + 1))
  elif [ "$STATUS" -eq 0 ]; then
    echo "  • $(basename "$DRAWIO_FILE") already in mxfile format"
  else
    echo "  WARNING: Could not normalize $(basename "$DRAWIO_FILE") ($NORMALIZE_RESULT)"
  fi
done
set -e

if [ "$DRAWIO_TOTAL" -eq 0 ]; then
  echo "  No .drawio files found in $(basename "$REPORT_DIR")"
else
  echo "  Normalized $DRAWIO_NORMALIZED of $DRAWIO_TOTAL draw.io file(s)"
fi

upload_attachment() {
  local FILE_PATH="$1"
  local MIME_TYPE="$2"
  local COMMENT_TEXT="$3"
  local FILE_NAME
  FILE_NAME="$(basename "$FILE_PATH")"

  local ATTACH_RESPONSE ATTACH_STATUS
  ATTACH_RESPONSE=$(curl -sS -w "\n%{http_code}" \
    -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X POST "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID/child/attachment" \
    -H "Accept: application/json" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${FILE_PATH};type=${MIME_TYPE}" \
    -F "comment=${COMMENT_TEXT}" 2>/dev/null)
  ATTACH_STATUS=$(echo "$ATTACH_RESPONSE" | tail -1)

  if [ "$ATTACH_STATUS" = "200" ] || [ "$ATTACH_STATUS" = "201" ]; then
    return 0
  fi

  # Confluence may return 400 when attachment name already exists; update attachment data in place.
  if [ "$ATTACH_STATUS" = "400" ]; then
    local ENCODED_NAME LOOKUP_RESPONSE EXISTING_ATTACHMENT_ID
    ENCODED_NAME=$(python3 - "$FILE_NAME" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
)
    LOOKUP_RESPONSE=$(curl -sS -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
      "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID/child/attachment?filename=$ENCODED_NAME&limit=1" \
      -H "Accept: application/json")
    EXISTING_ATTACHMENT_ID=$(echo "$LOOKUP_RESPONSE" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data['results'][0]['id'] if data.get('results') else '')" 2>/dev/null || true)

    if [ -n "$EXISTING_ATTACHMENT_ID" ]; then
      local UPDATE_RESPONSE UPDATE_STATUS
      UPDATE_RESPONSE=$(curl -sS -w "\n%{http_code}" \
        -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
        -X POST "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID/child/attachment/$EXISTING_ATTACHMENT_ID/data" \
        -H "Accept: application/json" \
        -H "X-Atlassian-Token: no-check" \
        -F "file=@${FILE_PATH};type=${MIME_TYPE}" \
        -F "comment=${COMMENT_TEXT}" \
        -F "minorEdit=true" 2>/dev/null)
      UPDATE_STATUS=$(echo "$UPDATE_RESPONSE" | tail -1)
      if [ "$UPDATE_STATUS" = "200" ] || [ "$UPDATE_STATUS" = "201" ]; then
        return 0
      fi
    fi
  fi

  return 1
}

DRAWIO_UPLOADED=0
set +e
for DRAWIO_FILE in "$REPORT_DIR"/*.drawio; do
  [ -f "$DRAWIO_FILE" ] || continue
  DRAWIO_NAME="$(basename "$DRAWIO_FILE")"
  echo "  Uploading draw.io: $DRAWIO_NAME"
  if upload_attachment "$DRAWIO_FILE" "application/vnd.jgraph.mxfile" "Editable draw.io source"; then
    echo "  ✓ Uploaded $DRAWIO_NAME"
    DRAWIO_UPLOADED=$((DRAWIO_UPLOADED + 1))
  else
    echo "  WARNING: Failed to upload/update $DRAWIO_NAME"
  fi
done
set -e

if [ "$DRAWIO_UPLOADED" -eq 0 ]; then
  echo "  No draw.io files uploaded (editable sources unavailable in Confluence attachments)"
else
  echo "  Uploaded $DRAWIO_UPLOADED draw.io file(s)"
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
echo "Diagrams: $DRAWIO_UPLOADED draw.io attachment(s) uploaded"
echo "URL:      $PAGE_URL"

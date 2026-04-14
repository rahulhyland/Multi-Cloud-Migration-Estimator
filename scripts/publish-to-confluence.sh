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

LATEST_REPORT=$(ls -t "$REPORTS_DIR"/multi-cloud-migration-report-*.md 2>/dev/null | head -1)
if [ -z "$LATEST_REPORT" ]; then
  echo "ERROR: No migration reports found in $REPORTS_DIR"
  exit 1
fi

echo "Found latest report: $(basename "$LATEST_REPORT")"

REPORT_TITLE=$(python3 - "$LATEST_REPORT" <<'PY'
import pathlib
import re
import sys

name = pathlib.Path(sys.argv[1]).name
match = re.match(r"multi-cloud-migration-report-(\d{8})-(\d{6})-utc\.md$", name)
if not match:
    raise SystemExit(f"Unexpected report filename: {name}")
date_part, time_part = match.groups()
print(
    f"Migration Report - {date_part[:4]}-{date_part[4:6]}-{date_part[6:8]} "
    f"{time_part[:2]}:{time_part[2:4]} UTC"
)
PY
)

echo "Report title: $REPORT_TITLE"
echo "Target space: $SPACE_KEY"

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

BODY_VALUE=$(python3 - "$LATEST_REPORT" <<'PY'
import html
import pathlib
import sys

content = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
print(f"<pre><code>{html.escape(content)}</code></pre>")
PY
)

if [ -z "$EXISTING_PAGE_ID" ]; then
  echo "✓ No existing page found. Creating a new page..."
  CREATE_PAYLOAD=$(python3 - "$SPACE_KEY" "$REPORT_TITLE" "$BODY_VALUE" <<'PY'
import json
import sys

space_key, title, body_value = sys.argv[1:4]
print(json.dumps({
    "type": "page",
    "title": title,
    "space": {"key": space_key},
    "body": {"storage": {"value": body_value, "representation": "storage"}}
}))
PY
)
  CREATE_RESPONSE=$(curl -sS -w "\n%{http_code}" -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X POST "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$CREATE_PAYLOAD")
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
  UPDATE_PAYLOAD=$(python3 - "$EXISTING_PAGE_ID" "$SPACE_KEY" "$REPORT_TITLE" "$BODY_VALUE" "$NEXT_VERSION" <<'PY'
import json
import sys

page_id, space_key, title, body_value, version = sys.argv[1:6]
print(json.dumps({
    "id": page_id,
    "type": "page",
    "title": title,
    "space": {"key": space_key},
    "body": {"storage": {"value": body_value, "representation": "storage"}},
    "version": {"number": int(version)}
}))
PY
)
  UPDATE_RESPONSE=$(curl -sS -w "\n%{http_code}" -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
    -X PUT "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$EXISTING_PAGE_ID" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_PAYLOAD")
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
echo "Step 3: Verifying published page..."
PAGE_DETAILS=$(curl -sS -u "$ATLASSIAN_API_EMAIL:$ATLASSIAN_API_TOKEN" \
  "$ATLASSIAN_API_ENDPOINT/wiki/rest/api/content/$PAGE_ID" \
  -H "Accept: application/json")
PAGE_WEBUI=$(echo "$PAGE_DETAILS" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('_links', {}).get('webui', ''))")
PAGE_URL="$ATLASSIAN_API_ENDPOINT/wiki${PAGE_WEBUI}"

echo ""
echo "================================"
echo "SUCCESS"
echo "================================"
echo "Title: $REPORT_TITLE"
echo "Page ID: $PAGE_ID"
echo "Local file: $(basename "$LATEST_REPORT")"
echo "URL: $PAGE_URL"

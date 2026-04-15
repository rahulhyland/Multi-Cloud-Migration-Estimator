#!/usr/bin/env bash
# generate-pdf.sh — Convert a markdown migration report to PDF.
# Usage: ./scripts/generate-pdf.sh <input.md> [output.pdf]
#
# One-time install (requires Node.js >= 18, no sudo needed):
#   npm install -g @mermaid-js/mermaid-cli md-to-pdf
#
# How it works:
#   1. Mermaid fenced blocks are rendered to PNG images via mmdc (local) or
#      the mermaid.ink public API (internet fallback, no install needed).
#   2. md-to-pdf converts the processed markdown to a styled PDF using
#      a headless Chromium instance — same engine as your browser, no LaTeX.

set -euo pipefail

INPUT="${1:?Usage: $0 <input.md> [output.pdf]}"
OUTPUT="${2:-${INPUT%.md}.pdf}"

# ── Security validations ───────────────────────────────────────────────────

# Input must exist and be a regular file
if [[ ! -f "${INPUT}" ]]; then
  echo "ERROR: Input file does not exist or is not a regular file: ${INPUT}" >&2
  exit 1
fi

# Resolve both paths to absolute and keep them inside the project root
REAL_INPUT=$(cd "$(dirname "${INPUT}")" && pwd)/$(basename "${INPUT}")
SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if [[ "${REAL_INPUT}" != "${SCRIPT_DIR}"/* ]]; then
  echo "ERROR: Input file must be within the project directory: ${SCRIPT_DIR}" >&2
  exit 1
fi

OUTPUT_DIR=$(cd "$(dirname "${OUTPUT}")" 2>/dev/null && pwd) || {
  echo "ERROR: Output directory does not exist: $(dirname "${OUTPUT}")" >&2
  exit 1
}
if [[ "${OUTPUT_DIR}" != "${SCRIPT_DIR}"/* && "${OUTPUT_DIR}" != "${SCRIPT_DIR}" ]]; then
  echo "ERROR: Output path must be within the project directory: ${SCRIPT_DIR}" >&2
  exit 1
fi
OUTPUT="${OUTPUT_DIR}/$(basename "${OUTPUT}")"

# ── Dependency checks ──────────────────────────────────────────────────────

if ! command -v md-to-pdf &>/dev/null; then
  echo "ERROR: md-to-pdf is not installed." >&2
  echo "  Run: npm install -g @mermaid-js/mermaid-cli md-to-pdf" >&2
  exit 1
fi

if ! command -v mmdc &>/dev/null; then
  echo "WARN: mmdc (Mermaid CLI) not found — Mermaid diagrams will be fetched" \
       "from mermaid.ink (requires internet). Install mmdc for offline rendering:" >&2
  echo "  npm install -g @mermaid-js/mermaid-cli" >&2
fi

echo "Input:  ${INPUT}"
echo "Output: ${OUTPUT}"

validate_headings_preserved() {
  local src_md="$1"
  local candidate_md="$2"
  python3 - "$src_md" "$candidate_md" <<'PY'
import re
import sys
from pathlib import Path

src_path = Path(sys.argv[1])
candidate_path = Path(sys.argv[2])

src = src_path.read_text(encoding="utf-8")
candidate = candidate_path.read_text(encoding="utf-8")

# Match markdown ATX headings only. This is the primary sectioning style used by reports.
heading_re = re.compile(r'^\s{0,3}#{1,6}\s+.+$', re.MULTILINE)
src_headings = heading_re.findall(src)
candidate_headings = heading_re.findall(candidate)

if src_headings != candidate_headings:
  print("ERROR: Markdown heading structure changed during PDF pre-processing.", file=sys.stderr)
  print(f"  source headings:    {len(src_headings)}", file=sys.stderr)
  print(f"  processed headings: {len(candidate_headings)}", file=sys.stderr)
  if src_headings:
    print(f"  first source heading:    {src_headings[0]}", file=sys.stderr)
  if candidate_headings:
    print(f"  first processed heading: {candidate_headings[0]}", file=sys.stderr)
  sys.exit(1)

print(f"Heading validation passed: {len(src_headings)} heading(s) preserved.")
PY
}

# ── Temp workspace ─────────────────────────────────────────────────────────
# A directory (not just a file) so Mermaid PNGs live alongside the markdown
# and md-to-pdf can resolve them via relative paths.
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/report-XXXXXX")
trap 'rm -rf "${TEMP_DIR}"' EXIT
chmod 700 "${TEMP_DIR}"
TEMP_MD="${TEMP_DIR}/processed.md"

# ── Mermaid pre-processing ─────────────────────────────────────────────────
echo "Pre-processing Mermaid diagrams…"
python3 "${SCRIPT_DIR}/scripts/preprocess-mermaid.py" "${REAL_INPUT}" "${TEMP_MD}"
validate_headings_preserved "${REAL_INPUT}" "${TEMP_MD}"

# ── Copy sibling image assets (SVG/PNG/JPG) so md-to-pdf resolves them ────
INPUT_DIR=$(dirname "${REAL_INPUT}")
for ext in svg png jpg jpeg gif webp; do
  for img in "${INPUT_DIR}"/*.${ext}; do
    [[ -f "${img}" ]] && cp "${img}" "${TEMP_DIR}/" && echo "Copied asset: $(basename "${img}")"
  done
done

# ── Inline image assets as base64 data URIs ────────────────────────────────
# Chromium blocks local file:// SVG loads in <img> tags. Inlining as data URIs
# ensures images always render in the PDF.
echo "Inlining image assets as data URIs…"
python3 - "${TEMP_MD}" <<'PY'
import base64
import mimetypes
import os
import re
import sys
from typing import Optional, Tuple
from pathlib import Path

md_path = Path(sys.argv[1])
content = md_path.read_text(encoding="utf-8")
img_dir = md_path.parent

img_re = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')

in_fence = False
out_lines = []
missing_assets = []

def resolve_local_image(src_raw: str) -> Optional[Tuple[str, str]]:
  src = src_raw.strip()
  if src.startswith("<") and src.endswith(">"):
    src = src[1:-1]

  # Ignore remote/data URLs.
  if src.startswith(("http://", "https://", "data:")):
    return None

  # Strip optional markdown title after a space, e.g. "file.svg \"title\""
  src = re.split(r'\s+".*"\s*$', src)[0]
  return src, str((img_dir / src).resolve())

for line in content.splitlines(keepends=True):
  if line.lstrip().startswith("```"):
    in_fence = not in_fence
    out_lines.append(line)
    continue

  if in_fence:
    out_lines.append(line)
    continue

  def repl(m: re.Match) -> str:
    alt = m.group(1)
    src_raw = m.group(2)
    resolved = resolve_local_image(src_raw)
    if resolved is None:
      return m.group(0)

    src, abs_img_path = resolved
    img_path = Path(abs_img_path)
    if not img_path.is_file():
      missing_assets.append(src)
      return m.group(0)

    mime, _ = mimetypes.guess_type(str(img_path))
    if mime and mime.startswith("image/svg"):
      mime = "image/svg+xml"
    elif not mime:
      mime = "image/png"

    encoded = base64.b64encode(img_path.read_bytes()).decode("ascii")
    print(f"  Inlined: {src} ({mime})", file=sys.stderr)
    return f'<img alt="{alt}" src="data:{mime};base64,{encoded}" />'

  out_lines.append(img_re.sub(repl, line))

if missing_assets:
  print("ERROR: Missing local image assets referenced by markdown:", file=sys.stderr)
  for item in sorted(set(missing_assets)):
    print(f"  - {item}", file=sys.stderr)
  sys.exit(1)

md_path.write_text("".join(out_lines), encoding="utf-8")
PY

validate_headings_preserved "${REAL_INPUT}" "${TEMP_MD}"

# ── Build runtime PDF config ───────────────────────────────────────────────
# Written to the temp dir so it is cleaned up automatically.
PDF_CONFIG="${TEMP_DIR}/pdf-config.json"
cat > "${PDF_CONFIG}" << JSON
{
  "stylesheet": ["${SCRIPT_DIR}/scripts/pdf-styles.css"],
  "highlight_style": "github",
  "launch_options": {
    "args": ["--force-light-mode", "--blink-settings=forceDarkModeEnabled=false"]
  },
  "pdf_options": {
    "format": "A4",
    "landscape": true,
    "margin": {
      "top":    "15mm",
      "right":  "15mm",
      "bottom": "15mm",
      "left":   "15mm"
    },
    "printBackground": true,
    "displayHeaderFooter": true,
    "headerTemplate": "<div style='font-size:8px;width:100%;text-align:right;padding-right:20mm;color:#888;font-family:sans-serif;'>Multi-Cloud Migration Report</div>",
    "footerTemplate": "<div style='font-size:8px;width:100%;text-align:center;color:#888;font-family:sans-serif;'>Page <span class='pageNumber'></span> of <span class='totalPages'></span></div>"
  }
}
JSON

# ── Generate PDF ───────────────────────────────────────────────────────────
echo "Generating PDF…"
# md-to-pdf always writes <input-basename>.pdf alongside the input file;
# we then move it to the caller-specified output path.
md-to-pdf \
  --config-file "${PDF_CONFIG}" \
  "${TEMP_MD}"

mv "${TEMP_DIR}/processed.pdf" "${OUTPUT}"
echo "PDF generated successfully: ${OUTPUT}"

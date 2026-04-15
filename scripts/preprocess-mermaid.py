#!/usr/bin/env python3
"""preprocess-mermaid.py — Render Mermaid fenced blocks to PNG images and
replace the fenced block with an inline base64 data URI image so md-to-pdf
always embeds the diagram in the generated PDF.

Usage:
    python3 preprocess-mermaid.py <input.md> <output.md>

PNG files are rendered temporarily and then inlined into markdown as
`data:image/png;base64,...` URLs.

Rendering priority:
  1. mmdc (Mermaid CLI)      — npm install -g @mermaid-js/mermaid-cli
  2. mermaid.ink public API  — requiress internet, no install needed
  3. Placeholder blockquote  — used when both above are unavailable
"""

import sys
import os
import re
import json
import base64
import shutil
import subprocess
import tempfile
import urllib.request
import urllib.error

MERMAID_FENCE_RE = re.compile(
    r"^```mermaid[ \t]*\n(.*?)^```[ \t]*$",
    re.MULTILINE | re.DOTALL,
)

# Rendering defaults tuned for PDF readability.
MERMAID_WIDTH = 1600
MERMAID_HEIGHT = 1200
MERMAID_SCALE = 2
MERMAID_FONT_SIZE = 24


def _mermaid_render_config() -> dict:
    """Central Mermaid config used by both mmdc and mermaid.ink."""
    return {
        "theme": "default",
        "themeVariables": {
            "fontSize": f"{MERMAID_FONT_SIZE}px",
        },
        "flowchart": {
            "nodeSpacing": 50,
            "rankSpacing": 70,
            "padding": 16,
            "htmlLabels": True,
            "useMaxWidth": False,
        },
        "sequence": {
            "actorFontSize": MERMAID_FONT_SIZE,
            "messageFontSize": MERMAID_FONT_SIZE,
            "noteFontSize": MERMAID_FONT_SIZE,
        },
        "gantt": {
            "fontSize": MERMAID_FONT_SIZE,
        },
    }


def _try_mmdc(diagram_code: str, output_png: str) -> bool:
    """Render via local mmdc binary."""
    mmdc = shutil.which("mmdc")
    if not mmdc:
        return False
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".mmd", delete=False
    ) as tmp:
        tmp.write(diagram_code)
        mmd_path = tmp.name

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False
    ) as cfg:
        json.dump(_mermaid_render_config(), cfg)
        cfg_path = cfg.name

    try:
        subprocess.run(
            [
                mmdc,
                "-i", mmd_path,
                "-o", output_png,
                "-b", "white",
                "--width", str(MERMAID_WIDTH),
                "--height", str(MERMAID_HEIGHT),
                "--scale", str(MERMAID_SCALE),
                "-c", cfg_path,
            ],
            check=True,
            capture_output=True,
            timeout=30,
        )
        return os.path.isfile(output_png) and os.path.getsize(output_png) > 100
    except Exception as exc:
        print(f"[mermaid] mmdc failed: {exc}", file=sys.stderr)
        return False
    finally:
        os.unlink(mmd_path)
        os.unlink(cfg_path)


def _try_mermaid_ink(diagram_code: str, output_png: str) -> bool:
    """Render via mermaid.ink public API (requires internet)."""
    payload = json.dumps(
        {"code": diagram_code, "mermaid": _mermaid_render_config()}
    )
    encoded = base64.urlsafe_b64encode(payload.encode("utf-8")).decode("ascii")
    url = (
        f"https://mermaid.ink/img/{encoded}?type=png"
        f"&width={MERMAID_WIDTH}&scale={MERMAID_SCALE}"
    )
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "generate-pdf-mermaid/1.0"}
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read()
        # Validate response is a real PNG (8-byte signature)
        if len(data) > 200 and data[:8] == b"\x89PNG\r\n\x1a\n":
            with open(output_png, "wb") as fh:
                fh.write(data)
            return True
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
        print(f"[mermaid] mermaid.ink failed: {exc}", file=sys.stderr)
    return False


def _placeholder(index: int) -> str:
    return (
        f"\n> **Diagram {index}** — *rendered in the `.md` file.*  \n"
        f"> To embed diagrams in the PDF install mmdc:  \n"
        f"> `npm install -g @mermaid-js/mermaid-cli`\n"
    )


def _png_data_uri(path: str) -> str:
    """Return a PNG file encoded as a data URI string."""
    with open(path, "rb") as fh:
        encoded = base64.b64encode(fh.read()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def process(input_path: str, output_path: str) -> None:
    output_dir = os.path.dirname(os.path.abspath(output_path))

    with open(input_path, "r", encoding="utf-8") as fh:
        content = fh.read()

    diagram_index = 0
    rendered: list[int] = []
    fallback: list[int] = []

    def replace_match(m: re.Match) -> str:
        nonlocal diagram_index
        diagram_index += 1
        idx = diagram_index
        diagram_code = m.group(1).strip()
        png_name = f"mermaid-diagram-{idx:02d}.png"
        png_path = os.path.join(output_dir, png_name)

        success = _try_mmdc(diagram_code, png_path) or _try_mermaid_ink(
            diagram_code, png_path
        )
        if success:
            rendered.append(idx)
            uri = _png_data_uri(png_path)
            # Use HTML img to avoid markdown URL escaping issues with long data URIs.
            return f'\n<img alt="Diagram {idx}" src="{uri}" />\n'
        fallback.append(idx)
        return _placeholder(idx)

    processed = MERMAID_FENCE_RE.sub(replace_match, content)

    with open(output_path, "w", encoding="utf-8") as fh:
        fh.write(processed)

    total = diagram_index
    if total == 0:
        print("[mermaid] No Mermaid diagrams found.", file=sys.stderr)
    else:
        if rendered:
            print(
                f"[mermaid] {len(rendered)}/{total} diagram(s) rendered → PNG: {rendered}",
                file=sys.stderr,
            )
        if fallback:
            print(
                f"[mermaid] {len(fallback)}/{total} diagram(s) → placeholder: {fallback}",
                file=sys.stderr,
            )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.md> <output.md>", file=sys.stderr)
        sys.exit(1)
    process(sys.argv[1], sys.argv[2])

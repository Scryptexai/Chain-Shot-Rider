#!/usr/bin/env bash
# Build the Godot 4.3 project into a WebAssembly build you can open in a browser.
#
#   bash tools/export_web.sh          # export to godot-web/
#   bash tools/export_web.sh --serve  # export, then serve it on :8080
#
# Everything it needs is inside this repo, because no Godot download host is
# reachable from the sandbox (see tools/web_template/README.md):
#   * engine  : Godot_v4.3-stable_linux.x86_64.zip   (repo root)
#   * template: tools/web_template/web_nothreads_release.zip
#
# The output in godot-web/ is deliberately NOT committed: it is 48 MB and this
# script regenerates it in a few seconds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENGINE_ZIP="$ROOT/Godot_v4.3-stable_linux.x86_64.zip"
CACHE="${GODOT_CACHE:-$HOME/.cache/godot/ex}"
GODOT="$CACHE/Godot_v4.3-stable_linux.x86_64"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.3.stable"
TEMPLATE_SRC="$ROOT/tools/web_template/web_nothreads_release.zip"
OUT="$ROOT/godot-web"

# 1. Engine. The cache is wiped between sandbox sessions, the zip is not.
if [ ! -x "$GODOT" ]; then
  [ -f "$ENGINE_ZIP" ] || { echo "ERROR: engine zip missing: $ENGINE_ZIP" >&2; exit 1; }
  echo "==> unpacking engine"
  mkdir -p "$CACHE" && unzip -o -q "$ENGINE_ZIP" -d "$CACHE" && chmod +x "$GODOT"
fi
echo "==> engine: $("$GODOT" --headless --version)"

# 2. Export template. Godot looks for it by an exact name in an exact folder.
if [ ! -f "$TEMPLATE_DIR/web_nothreads_release.zip" ]; then
  [ -f "$TEMPLATE_SRC" ] || { echo "ERROR: template missing: $TEMPLATE_SRC" >&2; exit 1; }
  echo "==> installing web template"
  mkdir -p "$TEMPLATE_DIR" && cp "$TEMPLATE_SRC" "$TEMPLATE_DIR/"
fi

# 3. Import. Required once per fresh checkout: the exporter packs .godot/,
#    and without this step the pack is missing every imported resource.
echo "==> importing project"
"$GODOT" --headless --path godot/ --import >/dev/null 2>&1 || true

# 4. Export.
echo "==> exporting"
mkdir -p "$OUT"
"$GODOT" --headless --path godot/ --export-release "Web" ../godot-web/index.html \
  2>&1 | grep -viE "^\s*savepack:|^$" || true

for f in index.html index.js index.wasm index.pck; do
  [ -s "$OUT/$f" ] || { echo "ERROR: export produced no $f" >&2; exit 1; }
done
echo "==> done:"
ls -la "$OUT" | awk 'NR>3 {printf "    %10.1f KB  %s\n", $5/1024, $9}'

if [ "${1:-}" = "--serve" ]; then
  echo "==> serving on http://0.0.0.0:8080/"
  exec python3 "$ROOT/tools/serve_web.py" 8080 godot-web
fi

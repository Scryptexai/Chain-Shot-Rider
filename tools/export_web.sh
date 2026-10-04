#!/usr/bin/env bash
# Mengekspor build Godot ke HTML5 supaya game bisa dicoba (dan di-debug) di
# browser, bukan cuma lewat tes headless.
#
# Dua template web yang dipakai — `web_nothreads_debug.zip` dan
# `web_nothreads_release.zip` — ada di akar repo. Versi "nothreads" dipilih
# karena varian ber-thread menuntut header COOP/COEP; tanpa header itu browser
# menolak SharedArrayBuffer dan layarnya hitam. Varian nothreads jalan di
# server statis apa adanya, termasuk preview sandbox ini.
#
#   bash tools/export_web.sh            # build debug (punya konsol + remote debug)
#   bash tools/export_web.sh release    # build release
#
# Setelah itu: python3 tools/serve_web.py 8090
set -euo pipefail

cd "$(dirname "$0")/.."
MODE="${1:-debug}"
VERSION="4.6.2.stable"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/$VERSION"

command -v godot >/dev/null || { echo "godot tidak ada — jalankan: bash tools/install_godot.sh 4.6.2-stable"; exit 1; }

# Godot mencari template di satu folder tetap per versi. Menyalin, bukan
# symlink: exporter membaca zip-nya berkali-kali dan symlink ke berkas repo
# bikin jejaknya membingungkan saat rollback workspace.
mkdir -p "$TEMPLATE_DIR"
for f in web_nothreads_debug.zip web_nothreads_release.zip; do
  [ -f "$f" ] || { echo "template $f hilang dari akar repo"; exit 1; }
  cp -f "$f" "$TEMPLATE_DIR/$f"
done
echo "template terpasang di $TEMPLATE_DIR"

mkdir -p build/web
# `--import` dulu: tanpa .godot/imported yang segar, exporter memaketkan
# tekstur versi lama dan karakternya tampil polos.
godot --headless --path godot/ --import >/dev/null
if [ "$MODE" = "release" ]; then
  godot --headless --path godot/ --export-release Web ../build/web/index.html
else
  godot --headless --path godot/ --export-debug Web ../build/web/index.html
fi

echo
echo "hasil:"
du -sh build/web
echo "jalankan: python3 tools/serve_web.py 8090"

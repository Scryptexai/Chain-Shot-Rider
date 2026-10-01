#!/usr/bin/env bash
# setup_chromium.sh — Menyiapkan Chromium headless untuk QA visual.
#
# Sandbox ini tidak bisa mengunduh Chromium dari CDN Google (koneksi TLS
# diputus), tetapi registry npm lolos. Paket @sparticuz/chromium membundel
# binary Chromium, SwiftShader (WebGL perangkat lunak), font, dan pustaka NSS
# di dalam tarball npm-nya, jadi semuanya bisa diambil dari sana.
#
# Hasil ekstrak ada di /tmp/chr dan TIDAK persisten: ulangi tiap sesi.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d node_modules/@sparticuz/chromium ] || npm install --no-save @sparticuz/chromium

mkdir -p /tmp/chr
node -e "
const z=require('zlib'),fs=require('fs');
const b='node_modules/@sparticuz/chromium/bin/';
fs.writeFileSync('/tmp/chr/chromium', z.brotliDecompressSync(fs.readFileSync(b+'chromium.br')));
for(const t of ['swiftshader','fonts','al2023'])
  fs.writeFileSync('/tmp/chr/'+t+'.tar', z.brotliDecompressSync(fs.readFileSync(b+t+'.tar.br')));
"
chmod +x /tmp/chr/chromium
cd /tmp/chr && for t in swiftshader fonts al2023; do tar -xf "$t.tar"; done

LD_LIBRARY_PATH=/tmp/chr/lib /tmp/chr/chromium --version
echo "Chromium siap di /tmp/chr/chromium"

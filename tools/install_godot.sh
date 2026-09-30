#!/usr/bin/env bash
# Universal Godot installer for sandboxes, CI, and local Linux boxes.
#
# Usage: bash tools/install_godot.sh [version]      e.g. 4.3-stable (default)
#
# Two things this script does differently from the usual one-liner, both
# learned the hard way in a locked-down sandbox:
#
#   1. It verifies what it downloaded. A blocked network usually answers with
#      an HTML error page, and `unzip` on that produces a confusing failure
#      three steps later. Here the file is checked before it is trusted.
#   2. It always installs the static toolchain (gdtoolkit), because that part
#      works from PyPI even when engine downloads are blocked, and it is what
#      lets you validate GDScript without the engine at all.
#
# Exit codes: 0 engine ready · 3 engine unavailable but validators installed.

set -uo pipefail

VERSION="${1:-4.3-stable}"
ARCH="linux.x86_64"
ZIP="Godot_v${VERSION}_${ARCH}.zip"
CACHE="${GODOT_CACHE:-$HOME/.cache/godot}"
VENV="${GODOT_VENV:-$HOME/.cache/venv}"

if [ -w /usr/local/bin ]; then BIN_DIR=/usr/local/bin; else BIN_DIR="$HOME/.local/bin"; fi
mkdir -p "$BIN_DIR" "$CACHE"

log() { printf '  %s\n' "$*"; }

# --- 1. already present? ----------------------------------------------------
if command -v godot >/dev/null 2>&1; then
  log "godot already installed: $(godot --version 2>/dev/null | head -1)"
  ENGINE_OK=1
else
  ENGINE_OK=0
fi

# --- 2. try to fetch the engine --------------------------------------------
# Mirrors are tried in order. Add your own with GODOT_MIRROR=<base-url>.
MIRRORS=(
  "${GODOT_MIRROR:-}"
  "https://github.com/godotengine/godot/releases/download/${VERSION}"
  "https://downloads.tuxfamily.org/godotengine/${VERSION%%-*}"
)

if [ "$ENGINE_OK" -eq 0 ]; then
  echo "Installing Godot ${VERSION}..."
  for base in "${MIRRORS[@]}"; do
    [ -z "$base" ] && continue
    log "trying ${base}"
    if curl -sSL --fail --max-time 300 -o "$CACHE/$ZIP" "${base}/${ZIP}" 2>/dev/null; then
      # A blocked proxy happily returns 200 with an HTML body. Check the magic
      # bytes instead of believing the exit code.
      if file "$CACHE/$ZIP" 2>/dev/null | grep -qi zip; then
        log "downloaded $(du -h "$CACHE/$ZIP" | cut -f1)"
        unzip -oq "$CACHE/$ZIP" -d "$CACHE" && \
        chmod +x "$CACHE/Godot_v${VERSION}_${ARCH}" && \
        ln -sf "$CACHE/Godot_v${VERSION}_${ARCH}" "$BIN_DIR/godot" && ENGINE_OK=1
        break
      fi
      log "response was not a zip archive (blocked or redirected); discarding"
      rm -f "$CACHE/$ZIP"
    fi
  done
fi

# --- 3. static toolchain, always ------------------------------------------
# Works from PyPI even when engine downloads are blocked. gdparse catches
# syntax errors, gdlint catches style and structure, gdformat normalises.
if ! "$VENV/bin/gdparse" --help >/dev/null 2>&1; then
  echo "Installing GDScript toolchain (gdtoolkit)..."
  python3 -m venv "$VENV" >/dev/null 2>&1
  "$VENV/bin/pip" install --quiet gdtoolkit==4.5.0 || log "gdtoolkit install failed"
fi
if "$VENV/bin/gdparse" --help >/dev/null 2>&1; then
  log "gdtoolkit ready: $("$VENV/bin/gdlint" --version 2>/dev/null)"
  log "add to PATH:  export PATH=\"$VENV/bin:\$PATH\""
fi

# --- 4. report -------------------------------------------------------------
echo
if [ "$ENGINE_OK" -eq 1 ]; then
  echo "Engine ready. Useful commands:"
  echo "  godot --headless --path godot/ --check-only       # compile check"
  echo "  godot --headless --path godot/ --quit             # boot once"
  echo "  bash tools/install_godot.sh 4.4-stable            # other version"
  exit 0
fi

cat <<'MSG'
Engine NOT installed — every mirror was unreachable.

This is expected in a restricted sandbox: godotengine.org and GitHub release
assets are commonly blocked while PyPI and npm stay open. Nothing is broken;
you simply cannot run the engine here.

What still works without the engine:
  python3 tools/validate_godot.py     # config keys, symbols, scene paths
  $VENV/bin/gdparse  <file.gd>        # syntax
  $VENV/bin/gdlint   godot/scripts    # style and structure
  $VENV/bin/gdformat --check godot/   # formatting

To get the engine here anyway, either set a reachable mirror:
  GODOT_MIRROR=https://your-host/godot bash tools/install_godot.sh
or download the zip on your own machine and drop it in, then re-run:
  ~/.cache/godot/Godot_v4.3-stable_linux.x86_64.zip
MSG
exit 3

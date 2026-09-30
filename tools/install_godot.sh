#!/usr/bin/env bash
# Universal Godot installer for sandboxes, CI, and local Linux boxes.
#
# Usage: bash tools/install_godot.sh [version]      e.g. 4.3-stable (default)
#
# Two things this script does differently from the usual one-liner, both
# learned the hard way in a locked-down sandbox:
#
#   1. It verifies what it downloaded by reading the magic bytes, not by
#      calling `file` (which many slim images do not ship) and not by trusting
#      curl's exit code. A blocked proxy answers 200 with an HTML error page,
#      and `unzip` on that fails three confusing steps later.
#   2. It looks for a zip you supplied by hand BEFORE touching the network,
#      so an offline sandbox works as long as the archive is somewhere obvious
#      (repo root, cwd, ~/Downloads, or the cache dir).
#   3. It always installs the static toolchain (gdtoolkit), because that part
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

# A zip starts with the bytes 50 4B 03 04. `file` is absent on slim images and
# curl reports success for a proxy's HTML error page, so read the bytes.
is_zip() {
  [ -s "$1" ] || return 1
  [ "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" = "504b0304" ]
}

# Unpacks an archive into the cache and links it onto PATH as `godot`.
install_from_zip() {
  local zip="$1"
  unzip -oq "$zip" -d "$CACHE" || return 1
  chmod +x "$CACHE/Godot_v${VERSION}_${ARCH}" || return 1
  ln -sf "$CACHE/Godot_v${VERSION}_${ARCH}" "$BIN_DIR/godot" || return 1
  log "installed from $zip"
}

# --- 1. already present? ----------------------------------------------------
if command -v godot >/dev/null 2>&1; then
  log "godot already installed: $(godot --version 2>/dev/null | head -1)"
  ENGINE_OK=1
else
  ENGINE_OK=0
fi

# --- 2. a zip supplied by hand beats any download ---------------------------
# Extraction targets the cache, never the repo: the binary is ~110 MB and has
# no business in version control or in a diff.
if [ "$ENGINE_OK" -eq 0 ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  for candidate in "$CACHE/$ZIP" "$REPO_ROOT/$ZIP" "$PWD/$ZIP" "$HOME/Downloads/$ZIP"; do
    [ -f "$candidate" ] || continue
    if is_zip "$candidate"; then
      echo "Found a local Godot archive, skipping download."
      install_from_zip "$candidate" && ENGINE_OK=1 && break
    else
      log "$candidate is not a zip archive; ignoring"
    fi
  done
fi

# --- 3. try to fetch the engine --------------------------------------------
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
      if is_zip "$CACHE/$ZIP"; then
        log "downloaded $(du -h "$CACHE/$ZIP" | cut -f1)"
        install_from_zip "$CACHE/$ZIP" && ENGINE_OK=1
        break
      fi
      log "response was not a zip archive (blocked or redirected); discarding"
      rm -f "$CACHE/$ZIP"
    fi
  done
fi

# --- 4. static toolchain, always ------------------------------------------
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

# --- 5. report -------------------------------------------------------------
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
or download the zip on your own machine and drop it in, then re-run. Any of
these locations is picked up automatically:
  <repo root>/Godot_v4.3-stable_linux.x86_64.zip
  ~/.cache/godot/Godot_v4.3-stable_linux.x86_64.zip
  ~/Downloads/Godot_v4.3-stable_linux.x86_64.zip
MSG
exit 3

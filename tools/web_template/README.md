# Godot 4.3 web export template (nothreads, release)

`web_nothreads_release.zip` is the export template the Godot editor needs to
produce a WebAssembly build. It is committed here on purpose.

## Why it is in git

Every route to the official download is blocked from this sandbox:

| Route | Result |
|---|---|
| `github.com/.../releases/download/...` | 302 to `release-assets.githubusercontent.com` |
| `release-assets.githubusercontent.com` (185.199.111.133) | connection refused |
| `objects.githubusercontent.com` (same IP) | connection refused |
| tuxfamily, jsDelivr, unpkg, archive.org, Docker Hub, ghcr.io | connection refused |

Only `pypi.org`, `registry.npmjs.org`, `github.com`, `api.github.com` and
`codeload.github.com` are reachable. The official `.tpz` is 1,023 MB and is
only published as a release asset, so it cannot be fetched here at all.

## Where the bytes come from

The GitHub **blob API** (`api.github.com`, reachable) serves any file from any
public repository as base64, up to 100 MB — bypassing the blocked CDN. The
runtime files were taken from a public Godot 4.3 web export
(`raidoon/godot-ninja_frog`, `docs/`), which is byte-identical to the official
template output: the exporter copies `.wasm`, `.js`, `.worklet.js` and the
icons out of the template unchanged and only ever rewrites the `.html`.

Verified before use:

- string inside the wasm: `Godot Engine v4.3.stable.official` — exactly the
  editor in this repo (`4.3.stable.official.77dcf97d8`)
- `pthread` 0 occurrences, `SharedArrayBuffer` 0 occurrences, `nothreads`
  present -> this is the **nothreads** variant
- that project's `export_presets.cfg` confirms `variant/thread_support=false`

`godot.html`, `godot.service.worker.js` and `godot.offline.html` are the
untouched shells from `misc/dist/html/` at tag `4.3-stable`, so the
`$GODOT_*` placeholders the exporter substitutes are intact.

Member names follow `platform/web/export/export_plugin.cpp`, which renames
every entry by replacing `godot` with the export basename.

## Why nothreads and not threads

The threaded template needs `SharedArrayBuffer`, which needs the
`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` pair. Inside an
embedded preview iframe the parent document is not cross-origin isolated, so a
threaded build shows a blank canvas there. The nothreads build has no such
requirement and runs anywhere.

## Licence

Godot Engine is MIT licensed; see `GODOT_LICENSE.txt`.
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

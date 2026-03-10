# EnvDraw

A browser-based environment diagram visualizer for Scheme, inspired by the
[SICP](https://mitp-content-server.mit.edu/books/content/sectbysect/6515/sicp.zip/index.html)
environment model of evaluation.

Type Scheme expressions into the REPL and watch the environment diagram
build in real time — frames, bindings, and closures rendered as a
force-directed SVG graph.

**Live site:** <https://jmacd.github.io/envdraw/>

## Architecture

```
Browser
├── index.html              loads D3 v7 (CDN), hoot/reflect.js, d3-diagram.js, boot.js
├── boot.js                 loads envdraw.wasm, wires REPL & toolbar, bridges FFI
├── d3-diagram.js           D3-force SVG rendering (frames, bindings, closures)
├── hoot/                   Guile Hoot runtime (copied by build, not source)
│   ├── reflect.js
│   ├── reflect.wasm
│   └── wtf8.wasm
└── style.css

Scheme → WebAssembly (via Guile Hoot)
├── web/envdraw.scm                    entry point: FFI bindings, primitives, boot!
├── src/core/meta.scm                  metacircular evaluator (view-eval, view-apply)
├── src/core/environments.scm          environment/frame/binding model
├── src/core/eval-observer.scm         observer interface
├── src/core/stacks.scm                stack data structures
├── src/model/color.scm                RGB color utilities
└── src/ui/web-observer.scm            emits D3 FFI calls for diagram updates
```

The evaluator runs entirely in WebAssembly. As it creates frames and
bindings, the observer emits FFI calls that `boot.js` bridges to the
`EnvDiagram` D3.js module, which maintains a live force-directed SVG.

## Prerequisites

- [Guile](https://www.gnu.org/software/guile/) 3.0
- [Guile Hoot](https://spritely.institute/hoot/)

On macOS with Homebrew:

```sh
brew tap aconchillo/guile
brew install guile guile-hoot
```

If you only change JS, CSS, or HTML files, you do not need Guile or Hoot —
skip straight to `./build.sh serve`.

## Building

```sh
./build.sh          # compile web/envdraw.wasm and bundle Hoot runtime
./build.sh clean    # remove envdraw.wasm and bundled runtime files
./build.sh serve    # start local dev server on http://localhost:8088/
```

The build compiles `web/envdraw.scm` (which `(include)`s all `src/` files)
to WebAssembly and copies the Hoot runtime into `web/hoot/`:

```sh
guild compile-wasm --bundle=web/hoot -L web -L . -o web/envdraw.wasm web/envdraw.scm
```

The `--bundle` flag copies `reflect.js`, `reflect.wasm`, and `wtf8.wasm`
from your Hoot installation. These files are gitignored — they are
regenerated on each build.

### Edit → rebuild cycle

1. Edit `.scm` file(s) under `src/` or `web/envdraw.scm`
2. Run `./build.sh`
3. Hard-refresh the browser (Cmd+Shift+R)

For JS/CSS/HTML changes, just save and refresh — no build step needed.

## Running locally

```sh
./build.sh          # first build (or after Scheme changes)
./build.sh serve    # open http://localhost:8088/
```

Requires a browser with WebAssembly GC and tail-call support
(Chrome 119+ / Firefox 120+ / Safari 18.2+).

## Deployment

Pushes to `main` automatically deploy `web/` to GitHub Pages via
`.github/workflows/deploy-pages.yml`. The workflow validates that all
required files exist, then uploads `web/` as a static site.

Since Guile Hoot is not available in CI, all build outputs must be
committed before pushing:

1. Edit Scheme source locally
2. Run `./build.sh`
3. Test with `./build.sh serve`
4. Commit the `.scm` changes, `web/envdraw.wasm`, and the `web/hoot/` files
5. Push to `main`

### Upgrading Hoot

```sh
brew upgrade guile-hoot
./build.sh                # --bundle copies updated runtime automatically
```

Test locally, then commit the updated `web/envdraw.wasm` and `web/hoot/`
files.

## History

EnvDraw was originally written in STk/Tk by Josh MacDonald and announced
on `comp.lang.scheme` in 1996 ([original announcement](original/ANNOUNCE)).
The original source is preserved in the `original/` directory.

This version is a ground-up rewrite targeting the browser, compiling
Scheme to WebAssembly via [Guile Hoot](https://spritely.institute/hoot/)
and rendering with [D3.js](https://d3js.org/).

## License

Copyright (C) 2026 Josh MacDonald

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
├── index.html          loads D3 v7 (CDN), reflect.js, d3-diagram.js, boot.js
├── boot.js             loads envdraw.wasm, wires REPL & toolbar, bridges FFI
├── d3-diagram.js       D3-force SVG rendering (frames, bindings, closures)
├── reflect.js          Guile Hoot WebAssembly runtime
└── style.css

Scheme → WebAssembly (via Guile Hoot)
├── web/envdraw.scm     entry point: FFI bindings, primitives, boot!
├── src/core/meta.scm   metacircular evaluator (view-eval, view-apply)
├── src/core/environments.scm   environment/frame/binding model
├── src/core/eval-observer.scm  observer interface
├── src/core/stacks.scm         stack data structures
├── src/model/color.scm         RGB color utilities
└── src/ui/web-observer.scm     emits D3 FFI calls for diagram updates
```

The evaluator runs entirely in WebAssembly. As it creates frames and
bindings, the observer emits FFI calls that `boot.js` bridges to the
`EnvDiagram` D3.js module, which maintains a live force-directed SVG.

## Prerequisites

To **rebuild** `envdraw.wasm` you need:

- [Guile](https://www.gnu.org/software/guile/) 3.0
- [Guile Hoot](https://spritely.institute/hoot/) 0.6.1

On macOS with Homebrew:

```sh
brew install guile guile-hoot
```

> **Note:** `envdraw.wasm` and the Hoot runtime files (`reflect.wasm`,
> `wtf8.wasm`) are checked into the repository, so you only need the
> toolchain if you modify the Scheme sources.

## Building

```sh
./build.sh          # compile web/envdraw.wasm
./build.sh clean    # remove envdraw.wasm
./build.sh serve    # start local dev server on http://localhost:8088/
```

The build compiles `web/envdraw.scm` (which `(include)`s all `src/` files)
to WebAssembly:

```sh
guild compile-wasm -L web -L . -o web/envdraw.wasm web/envdraw.scm
```

## Running locally

```sh
./build.sh serve
# open http://localhost:8088/
```

Requires a browser with WebAssembly GC and tail-call support
(Chrome 119+ / Firefox 120+).

## Deployment

Pushes to `main` automatically deploy `web/` to GitHub Pages via the
workflow in `.github/workflows/deploy-pages.yml`.

## Browser requirements

- WebAssembly GC proposal
- WebAssembly tail calls
- Chrome 119+ / Firefox 120+ / Safari 18.2+

## History

EnvDraw was originally written in STk/Tk by Josh MacDonald and announced
on `comp.lang.scheme` in 1996 ([original announcement](original/ANNOUNCE)).
The original source is preserved in the `original/` directory.

This version is a ground-up rewrite targeting the browser, compiling
Scheme to WebAssembly via [Guile Hoot](https://spritely.institute/hoot/)
and rendering with [D3.js](https://d3js.org/).

## License

Copyright (C) 2026 Josh MacDonald

#!/bin/sh
# build.sh — Build EnvDraw Wasm artifacts
#
# Prerequisites:
#   Guile 3.0 + Guile Hoot 0.6.1
#   macOS:  brew install guile guile-hoot
#
# Usage:
#   ./build.sh          # build web/envdraw.wasm
#   ./build.sh clean    # remove envdraw.wasm (keeps runtime .wasm files)
#   ./build.sh serve    # start local dev server on :8088
#
# The Hoot runtime files (reflect.wasm, wtf8.wasm) are checked into
# web/ and do not need rebuilding.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Guile/Hoot load paths — adjust if installed elsewhere
export GUILE_LOAD_PATH="/opt/homebrew/share/guile/site/3.0${GUILE_LOAD_PATH:+:}$GUILE_LOAD_PATH"
export GUILE_LOAD_COMPILED_PATH="/opt/homebrew/lib/guile/3.0/site-ccache${GUILE_LOAD_COMPILED_PATH:+:}$GUILE_LOAD_COMPILED_PATH"

compile_one() {
    local src="$1"
    local out="${src%.scm}.wasm"
    echo "==> Compiling $out ..."
    time guild compile-wasm \
        -L web -L . \
        -o "$out" \
        "$src"
    ls -lh "$out" | awk '{print "    Output:", $5, $9}'
    echo ""
}

case "${1:-main}" in
    main)
        compile_one web/envdraw.scm
        ;;
    clean)
        echo "==> Removing envdraw.wasm"
        rm -f web/envdraw.wasm
        echo "    Done."
        ;;
    serve)
        echo "==> Serving on http://localhost:8088/"
        cd web && python3 -m http.server 8088
        ;;
    *)
        echo "Usage: $0 [main|clean|serve]"
        exit 1
        ;;
esac

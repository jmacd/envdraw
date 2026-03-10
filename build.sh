#!/bin/sh
# build.sh — Build EnvDraw Wasm artifacts
#
# Prerequisites:
#   Guile 3.0 + Guile Hoot
#   macOS:  brew install guile guile-hoot
#
# Usage:
#   ./build.sh          # build web/envdraw.wasm + bundle Hoot runtime
#   ./build.sh clean    # remove build outputs
#   ./build.sh serve    # start local dev server on :8088

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
        --bundle=web/hoot \
        -L web -L . \
        -o "$out" \
        "$src"
    ls -lh "$out" | awk '{print "    Output:", $5, $9}'
    echo "    Hoot runtime bundled into web/hoot/"
    echo ""
}

case "${1:-main}" in
    main)
        compile_one web/envdraw.scm
        ;;
    clean)
        echo "==> Removing build outputs"
        rm -f web/envdraw.wasm
        rm -f web/hoot/reflect.js web/hoot/reflect.wasm web/hoot/wtf8.wasm
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

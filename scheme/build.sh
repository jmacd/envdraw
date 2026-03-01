#!/bin/sh
# build.sh — Build EnvDraw Wasm artifacts
#
# Usage:
#   ./build.sh          # build main envdraw.wasm
#   ./build.sh test     # build envdraw-test.wasm
#   ./build.sh tmp      # build web/tmp-test.wasm
#   ./build.sh all      # build main + test
#   ./build.sh clean    # remove .wasm outputs
#   ./build.sh FILE.scm # compile an arbitrary .scm in web/
#
# Automatically sources env.sh for Guile/Hoot paths.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Source environment
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
    test)
        compile_one web/envdraw-test.scm
        ;;
    tmp)
        compile_one web/tmp-test.scm
        ;;
    all)
        compile_one web/envdraw.scm
        compile_one web/envdraw-test.scm
        ;;
    clean)
        echo "==> Removing .wasm outputs"
        rm -f web/*.wasm
        echo "    (kept reflect.wasm and wtf8.wasm)"
        # restore runtime wasm
        cp /opt/homebrew/Cellar/guile-hoot/0.6.1/share/guile-hoot/0.6.1/reflect-wasm/reflect.wasm web/
        cp /opt/homebrew/Cellar/guile-hoot/0.6.1/share/guile-hoot/0.6.1/wtf8-wasm/wtf8.wasm web/
        echo "    Done."
        ;;
    *.scm)
        if [ -f "web/$1" ]; then
            compile_one "web/$1"
        elif [ -f "$1" ]; then
            compile_one "$1"
        else
            echo "File not found: $1"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [main|test|tmp|all|clean|FILE.scm]"
        exit 1
        ;;
esac

echo "Done.  Reload http://localhost:8088/ (cache-buster in boot.js)"

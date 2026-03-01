#!/bin/sh
# Source this file to set up the EnvDraw development environment:
#   source env.sh

export GUILE_LOAD_PATH="/opt/homebrew/share/guile/site/3.0${GUILE_LOAD_PATH:+:}$GUILE_LOAD_PATH"
export GUILE_LOAD_COMPILED_PATH="/opt/homebrew/lib/guile/3.0/site-ccache${GUILE_LOAD_COMPILED_PATH:+:}$GUILE_LOAD_COMPILED_PATH"

echo "EnvDraw dev environment ready."
echo "  Guile: $(guile --version | head -1)"
echo "  Hoot:  $(guile -c '(use-modules (hoot config)) (display %version) (newline)' 2>/dev/null || echo 'not found')"

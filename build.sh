#!/bin/sh

set -e

if [[ $1 == "debug" ]]; then
    echo Debug build, not minified.
    MINIFY=cat
    DEBUG_CODE=html/src/fakeworker-0.1.js
else
    MINIFY=jsmin
    DEBUG_CODE=
fi

# Worker thread (plain JS version)
(
    cat html/src/header.js
    (
        coffee -c -p html/src/worker-noasm.coffee
    ) | $MINIFY
) > html/rayworker.js

# Worker thread (asm.js version)
(
    cat html/src/header.js
    (
        cat html/src/worker-asm-core.js
        coffee -c -p html/src/worker-asm-shell.coffee
    ) | $MINIFY
) > html/rayworker-asm.js

# Main file
(
    cat html/src/header.js
    (
        cat \
            html/src/jquery-1.9.1.min.js \
            html/src/jquery.hotkeys.js \
            html/src/asmjs-feature-test.js \
            $DEBUG_CODE
        (
            cat \
                html/src/zen-renderer.coffee \
                html/src/zen-widgets.coffee \
                html/src/zen-ui.coffee \
                html/src/zen-setup.coffee
        ) | coffee -p -s
    ) | $MINIFY
) > html/zenphoton.js

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

# Worker thread
(
    cat html/src/header.js
    (
        cat html/src/rayworker-asm.js
        coffee -c -p html/src/rayworker.coffee
    ) | $MINIFY
) > html/rayworker.js

# Main file
(
    cat html/src/header.js
    (
        cat \
            html/src/jquery-1.9.1.min.js \
            html/src/jquery.hotkeys.js \
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

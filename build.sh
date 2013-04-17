#!/bin/sh

set -e

if [[ $1 == "debug" ]]; then
    echo Debug build, not minified.
    MINIFY=cat
else
    MINIFY=jsmin
fi

# Worker thread
(
    cat html/src/header.js
    (
        coffee -c -p html/src/rayworker.coffee
    ) | $MINIFY
) > html/rayworker.js

# Main file
(
    cat html/src/header.js
    (
        cat html/src/jquery-1.9.1.min.js
        cat html/src/jquery.hotkeys.js
        (
            cat html/src/zen-renderer.coffee
            cat html/src/zen-widgets.coffee
            cat html/src/zen-ui.coffee
            cat html/src/zen-setup.coffee
        ) | coffee -p -s
    ) | $MINIFY
) > html/zenphoton.js

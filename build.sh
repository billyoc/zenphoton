#!/bin/sh

set -e

# Worker thread
(
    cat html/src/header.js
    (
        cat html/src/rayworker-asm.js
        coffee -c -p html/src/rayworker.coffee
    ) | jsmin
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
    ) | jsmin
) > html/zenphoton.js

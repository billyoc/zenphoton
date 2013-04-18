#!/bin/sh

set -e
./build.sh

FILES="\
    html/zenphoton.js       \
    html/rayworker.js       \
    html/rayworker-asm.js   \
    html/index.html         \
    html/missing.html       \
    html/favicon.gif        \
    html/favicon.ico        \
    html/roboto.ttf         "

scp $FILES scanlime@scanlime.org:~/zenphoton.com/

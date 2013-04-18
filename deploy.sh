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
    html/logo-57.png        \
    html/logo-72.png        \
    html/logo-114.png       \
    html/logo-144.png       \
    html/roboto.ttf         "

scp $FILES scanlime@scanlime.org:~/zenphoton.com/

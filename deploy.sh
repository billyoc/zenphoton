#!/bin/sh

set -e
./build.sh

FILES="html/*.js html/*.html html/*.gif html/*.ico html/*.ttf"

scp $FILES scanlime@scanlime.org:~/zenphoton.com/

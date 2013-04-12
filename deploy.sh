#!/bin/sh

coffee -c html
FILES="html/*.js html/*.html html/*.gif html/*.ico"
scp $FILES scanlime@scanlime.org:~/zenphoton.com/


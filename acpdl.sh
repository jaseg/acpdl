#!/bin/sh

mkdir acpdl.$$
sed 's,^\s*<location>\(.*\)</location>\s*$,\1,;t;d' "$*" | xargs wget -P acpdl.$$
cd acpdl.$$ 
id3 -2 -f "%n %a - %t.mp3" '*'

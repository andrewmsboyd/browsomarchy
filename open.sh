#!/bin/bash

# The Exec= command of Browsomarchy's desktop entry: what runs whenever the
# system opens a browser with Browsomarchy as the default.
#
# Usage: open.sh [url] [--incognito]
#
# omarchy-launch-browser takes the first word of the default browser's Exec=
# and runs it like a browser: with a URL, with no arguments to open a window,
# or with a private-window flag. It also runs it with --help to tell which
# flag a browser takes, so --help has to return without opening the picker.

url=""
incognito=false

for arg in "$@"; do
  case $arg in
  -h | --help)
    echo "usage: open.sh [url] [--incognito]"
    exit 0
    ;;
  --incognito | --private-window | --inprivate | --private) incognito=true ;;
  -*) ;;
  *) [[ -n $url ]] || url=$arg ;;
  esac
done

exec omarchy-shell browsomarchy choose "$url" "$incognito"

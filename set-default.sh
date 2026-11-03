#!/bin/bash

# Makes a desktop entry the system's handler for web links.
#
# Usage: set-default.sh <desktop-id>
#
# xdg-mime/xdg-settings only write mimeapps.list. A desktop-specific list
# (e.g. ~/.config/hyprland-mimeapps.list) is read before it, and Omarchy
# 4.0.6+ ships one that sends http/https to omarchy-browser.desktop, which
# relaunches the default browser's Exec= binary without its arguments. So
# also point http/https at <desktop-id> in any desktop-specific list that
# already exists for the current desktop.

set -o pipefail

desktop_id="$1"

if [[ -z $desktop_id ]]; then
  echo "usage: set-default.sh <desktop-id>" >&2
  exit 1
fi

config="${XDG_CONFIG_HOME:-$HOME/.config}"

xdg-mime default "$desktop_id" \
  x-scheme-handler/http x-scheme-handler/https text/html \
  x-scheme-handler/about x-scheme-handler/unknown || exit 1

# Sets each mime type in the list's [Default Applications] section, leaving
# every other line and section alone.
set_handlers() {
  local list=$1
  local tmp

  tmp=$(mktemp) || return 1
  awk -v id="$desktop_id" '
    function add_missing() {
      if (!set["x-scheme-handler/http"]) print "x-scheme-handler/http=" id
      if (!set["x-scheme-handler/https"]) print "x-scheme-handler/https=" id
      added = 1
    }
    /^\[/ {
      if (section && !added) add_missing()
      section = ($0 == "[Default Applications]")
      seen = seen || section
      print
      next
    }
    section && /^x-scheme-handler\/https?=/ {
      mime = substr($0, 1, index($0, "=") - 1)
      print mime "=" id
      set[mime] = 1
      next
    }
    { print }
    END {
      if (section && !added) add_missing()
      if (!seen) {
        print ""
        print "[Default Applications]"
        add_missing()
      }
    }
  ' "$list" >"$tmp" && cat "$tmp" >"$list"
  rm -f "$tmp"
}

IFS=: read -ra desktops <<<"${XDG_CURRENT_DESKTOP:-}"
for desktop in "${desktops[@]}"; do
  [[ -n $desktop ]] || continue
  list="$config/${desktop,,}-mimeapps.list"
  [[ -f $list ]] && set_handlers "$list"
done

# Runs after the desktop-specific lists are updated: it reads the handler
# back after writing, and restores the old one if a list still overrides it.
# Omarchy's session sets $BROWSER, which xdg-settings refuses to override.
env -u BROWSER xdg-settings set default-web-browser "$desktop_id"

update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" 2>/dev/null || true

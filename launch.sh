#!/bin/bash

# Launches a URL in a specific browser, chosen by desktop-entry id.
#
# Usage: launch.sh <desktop-id> <url> [--incognito]
#
# The normal path defers entirely to gtk-launch (same mechanism the app
# launcher already uses in AppLibrary.qml) so %u/%U field-code handling and
# Terminal= stay correct. Incognito can't go through gtk-launch (there's no
# way to inject an extra flag into someone else's Exec= line), so it falls
# back to resolving the binary and picking a private-window flag the same
# way /usr/share/omarchy/bin/omarchy-launch-browser already does.
#
# Either path finishes by focusing the resulting window via
# omarchy-hyprland-focus-app (same helper omarchy-launch-browser uses) — a
# browser reusing its existing window on another workspace is otherwise
# left behind there instead of being brought to the one the link was
# opened from.

set -o pipefail

desktop_id="$1"
url="$2"
mode="${3:-}"

if [[ -z $desktop_id || -z $url ]]; then
  echo "usage: launch.sh <desktop-id> <url> [--incognito]" >&2
  exit 1
fi

focus_app() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
  # Small buffer for a cold-started browser to map its first window before
  # we go looking for it; near-instant for the already-running case this
  # exists for.
  sleep 0.2
  omarchy-hyprland-focus-app "^${desktop_id%.desktop}$" >/dev/null 2>&1 || true
}

if [[ $mode != "--incognito" ]]; then
  uwsm-app -- gtk-launch "$desktop_id" "$url"
  focus_app
  exit 0
fi

browser_exec=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' {~/.local,~/.nix-profile,/usr}/share/applications/"$desktop_id" 2>/dev/null | head -1)

if [[ -z $browser_exec ]]; then
  uwsm-app -- gtk-launch "$desktop_id" "$url"
  focus_app
  exit 0
fi

if "$browser_exec" --help 2>/dev/null | grep -q MOZ_LOG; then
  private_flag="--private-window"
elif [[ $browser_exec =~ edge ]]; then
  private_flag="--inprivate"
else
  private_flag="--incognito"
fi

uwsm-app -- "$browser_exec" "$private_flag" --new-window "$url"
focus_app

#!/bin/bash

# Emits one JSON line per installed .desktop entry that advertises it can
# handle x-scheme-handler/http or /https (i.e. every "web browser" the OS
# knows about). Quickshell's own DesktopEntries singleton parses .desktop
# files for us (name/icon/exec), but it does not expose MimeType=, so this
# script does the one thing it's missing: find the candidate ids. Callers
# resolve display info for each id via DesktopEntries.byId(id).
#
# Usage: scan-browsers.sh [self-desktop-id-to-exclude]

set -o pipefail

self_id="${1:-}"

declare -A seen
declare -A dirs

dirs["$HOME/.local/share/applications"]=1
IFS=':' read -ra data_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for d in "${data_dirs[@]}"; do
  [[ -n $d ]] && dirs["$d/applications"]=1
done

for dir in "${!dirs[@]}"; do
  [[ -d $dir ]] || continue

  while IFS= read -r -d '' file; do
    rel=${file#"$dir"/}
    id=${rel//\//-}

    [[ -n ${seen[$id]:-} ]] && continue
    [[ $id == "$self_id" ]] && continue

    mimetypes=$(grep -m1 '^MimeType=' "$file")
    [[ $mimetypes == *x-scheme-handler/http* ]] || continue

    grep -qm1 '^NoDisplay=true' "$file" && continue
    grep -qm1 '^Hidden=true' "$file" && continue

    seen[$id]=1
    jq -cn --arg id "$id" '{id: $id}'
  done < <(find "$dir" -maxdepth 4 -name '*.desktop' -print0 2>/dev/null)
done

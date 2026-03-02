#!/usr/bin/env bash
# Host-side clipboard watcher for AgentBox (macOS only).
# Monitors the system clipboard for image data and writes PNG to a shared
# directory that the container-side xclip shim reads from.
#
# The clipboard is never modified. The image path is written to
# ~/.agentbox/clipboard-path for the Cmd+Shift+C workflow to use.

set -euo pipefail

if [[ "$OSTYPE" != darwin* ]]; then
    echo "Unsupported platform: clipboard bridge requires macOS" >&2
    exit 1
fi

clipboard_dir="$1"
clipboard_file="${clipboard_dir}/clipboard.png"
path_file="$HOME/.agentbox/clipboard-path"

mkdir -p "$clipboard_dir"
mkdir -p "$HOME/.agentbox"

cleanup() {
    rm -f "$clipboard_file"
    rm -f "$path_file"
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

POLL_INTERVAL=0.5

check_clipboard() {
    osascript <<'APPLESCRIPT' 2>/dev/null
use framework "AppKit"
set pb to current application's NSPasteboard's generalPasteboard()
set cc to pb's changeCount() as integer
set hasImage to false
set pngType to current application's NSPasteboardTypePNG
set tiffType to current application's NSPasteboardTypeTIFF
if ((pb's types()'s containsObject:pngType) as boolean) or ((pb's types()'s containsObject:tiffType) as boolean) then
    set hasImage to true
end if
return (cc as text) & " " & (hasImage as text)
APPLESCRIPT
}

save_clipboard() {
    osascript - "$1" <<'APPLESCRIPT' 2>/dev/null
use framework "AppKit"
use framework "Foundation"
on run argv
    set pb to current application's NSPasteboard's generalPasteboard()
    set imgData to pb's dataForType:(current application's NSPasteboardTypePNG)
    if imgData is missing value then
        set tiffData to pb's dataForType:(current application's NSPasteboardTypeTIFF)
        if tiffData is not missing value then
            set theRep to current application's NSBitmapImageRep's imageRepWithData:tiffData
            set imgData to theRep's representationUsingType:(current application's NSBitmapImageFileTypePNG) |properties|:(missing value)
        end if
    end if
    if imgData is not missing value then
        imgData's writeToFile:(item 1 of argv) atomically:true
    end if
end run
APPLESCRIPT
}

# --- Main loop ---

last_change_count=""

while true; do
    info=$(check_clipboard) || { sleep "$POLL_INTERVAL"; continue; }

    cc="${info%% *}"
    has_image="${info##* }"

    if [[ "$cc" != "$last_change_count" ]]; then
        last_change_count="$cc"
        if [[ "$has_image" == "true" ]]; then
            save_clipboard "$clipboard_file" >/dev/null || true
            echo "$clipboard_file" > "$path_file"
        else
            rm -f "$clipboard_file"
            rm -f "$path_file"
        fi
    fi

    sleep "$POLL_INTERVAL"
done

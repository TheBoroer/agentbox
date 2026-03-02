#!/usr/bin/env bash
set -euo pipefail

IMAGE_DIR="/tmp/clipboard-images"
mkdir -p "$IMAGE_DIR"

if ! osascript -e 'clipboard info' 2>/dev/null | grep -qE 'PNGf|TIFF'; then
    osascript -e 'display notification "No image in clipboard" with title "AgentBox"'
    exit 0
fi

FILENAME="clipboard.png"
FILEPATH="$IMAGE_DIR/$FILENAME"

osascript -e "
set imgData to the clipboard as «class PNGf»
set filePath to POSIX file \"$FILEPATH\"
set fileRef to open for access filePath with write permission
write imgData to fileRef
close access fileRef
" 2>/dev/null

if [[ ! -f "$FILEPATH" ]]; then
    osascript -e 'display notification "Failed to save image" with title "AgentBox"'
    exit 1
fi

echo -n "$FILEPATH" | pbcopy
osascript -e "display notification \"Copied path\" with title \"Image Saved\""

#!/usr/bin/env bash
# xclip shim for AgentBox clipboard image bridge.
# Installed as /usr/local/bin/xclip in the container. Intercepts Claude Code's
# clipboard read calls and returns image data from the host-synced file.

clipboard_file="${PROJECT_DIR}/.agentbox-clipboard/clipboard.png"

has_output=false
target=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) has_output=true; shift ;;
        -t) shift; target="${1:-}"; shift ;;
        *) shift ;;
    esac
done

# Write operations (no -o flag) are a no-op
if [[ "$has_output" != "true" ]]; then
    exit 0
fi

case "$target" in
    TARGETS)
        if [[ -f "$clipboard_file" ]]; then
            echo "image/png"
            exit 0
        fi
        exit 1
        ;;
    image/png)
        if [[ -f "$clipboard_file" ]]; then
            cat "$clipboard_file"
            exit 0
        fi
        exit 1
        ;;
    text/plain)
        # Return image file path so Claude Code's path detection can find it
        if [[ -f "$clipboard_file" ]]; then
            echo "$clipboard_file"
            exit 0
        fi
        exit 1
        ;;
    *)
        exit 1
        ;;
esac

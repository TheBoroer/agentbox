#!/usr/bin/env bash
# Host-side audio bridge for AgentBox (macOS only).
# Polls a shared directory for play requests and plays them using afplay.
# Uses regular files instead of FIFOs because named pipes don't work
# across Docker's VM boundary on macOS.

set -euo pipefail

if [[ "$OSTYPE" != darwin* ]]; then
    echo "Unsupported platform: audio bridge requires macOS" >&2
    exit 1
fi

audio_dir="$1"
request_file="${audio_dir}/play.request"

cleanup() {
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

play_sound() {
    pkill -x afplay 2>/dev/null || true
    afplay "$1" &
}

while true; do
    if [[ -f "$request_file" ]]; then
        sound_path=$(cat "$request_file")
        rm -f "$request_file"

        if [[ -n "$sound_path" && -f "$sound_path" ]]; then
            play_sound "$sound_path"
        elif [[ -n "$sound_path" ]]; then
            echo "agentbox audio-bridge: file not found: $sound_path" >&2
        fi
    fi

    sleep 0.3
done

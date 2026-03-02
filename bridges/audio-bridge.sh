#!/usr/bin/env bash
# Host-side audio bridge for AgentBox.
# Polls a shared directory for play requests and plays them using
# platform-native commands. Uses regular files instead of FIFOs because
# named pipes don't work across Docker's VM boundary on macOS.
# Supports macOS (afplay) and Windows via WSL2 (PowerShell SoundPlayer).

set -euo pipefail

audio_dir="$1"
request_file="${audio_dir}/play.request"

cleanup() {
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

if [[ "$OSTYPE" == darwin* ]]; then
    play_sound() {
        pkill -x afplay 2>/dev/null || true
        afplay "$1" &
    }
elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    play_sound() {
        local win_path
        win_path=$(wslpath -w "$1" 2>/dev/null) || return
        powershell.exe -NoProfile -Command "(New-Object System.Media.SoundPlayer '$win_path').PlaySync()" &
    }
else
    echo "Unsupported platform: audio bridge requires macOS or WSL2" >&2
    exit 1
fi

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

#!/usr/bin/env bash
# Container-side shim for AgentBox audio bridge.
# Installed as /usr/local/bin/agentbox-play in the container.
# Writes a host-side file path to the audio bridge request file.

request="/home/agent/.agentbox-audio/play.request"

[[ -z "${1:-}" ]] && exit 0
[[ -d "$(dirname "$request")" ]] || exit 0

echo "$1" > "$request" 2>/dev/null || true

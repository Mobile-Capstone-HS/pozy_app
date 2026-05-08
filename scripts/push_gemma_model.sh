#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <device_id> <local_model_path>" >&2
  echo "Example: $0 R3CWA0602GK ~/Downloads/gemma4_e2b.litertlm" >&2
  exit 64
fi

DEVICE_ID="$1"
LOCAL_MODEL_PATH="${2/#\~/$HOME}"
DEVICE_DIR="/data/local/tmp/llm"
DEVICE_PATH="$DEVICE_DIR/$(basename "$LOCAL_MODEL_PATH")"

if [ ! -f "$LOCAL_MODEL_PATH" ]; then
  echo "Local model file not found: $LOCAL_MODEL_PATH" >&2
  exit 66
fi

adb -s "$DEVICE_ID" shell mkdir -p "$DEVICE_DIR"
adb -s "$DEVICE_ID" push "$LOCAL_MODEL_PATH" "$DEVICE_PATH"
adb -s "$DEVICE_ID" shell ls -lh "$DEVICE_PATH"

echo "Gemma model pushed to: $DEVICE_PATH"

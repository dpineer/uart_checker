#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Candidate locations for the built binary, ordered by preference (latest build first)
CANDIDATES=(
  "$SCRIPT_DIR/build/linux/x64/release/bundle/uart_checker"
  "$SCRIPT_DIR/Release/Linux/bundle/uart_checker"
)

BINARY=""
for c in "${CANDIDATES[@]}"; do
  if [ -f "$c" ]; then
    BINARY="$c"
    break
  fi
done

if [ -z "$BINARY" ]; then
  echo "Error: uart_checker binary not found. Build the project first." >&2
  exit 1
fi

chmod +x "$BINARY"

BUNDLE_DIR="$(dirname "$BINARY")"
exec "$BINARY" --working-dir="$BUNDLE_DIR"

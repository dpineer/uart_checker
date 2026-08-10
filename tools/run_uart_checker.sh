#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Candidate locations for the built binary
CANDIDATES=(
  "$SCRIPT_DIR/build/linux/x64/release/bundle/uart_checker"
  "$SCRIPT_DIR/build/linux/x64/debug/bundle/uart_checker"
  "$SCRIPT_DIR/Release/Linux/bundle/uart_checker"
)

# Select the most recently compiled bundle. Dart code changes are compiled into
# lib/libapp.so (the uart_checker executable stub is rarely rebuilt), so compare
# the libapp.so modification time to determine the latest version.
BINARY=""
BINARY_MTIME=0
for c in "${CANDIDATES[@]}"; do
  if [ -f "$c" ]; then
    APP_LIB="$(dirname "$c")/lib/libapp.so"
    MTIME=$(stat -c %Y "$APP_LIB" 2>/dev/null || stat -c %Y "$c" 2>/dev/null || echo 0)
    if [ "$MTIME" -ge "$BINARY_MTIME" ]; then
      BINARY="$c"
      BINARY_MTIME="$MTIME"
    fi
  fi
done

if [ -z "$BINARY" ]; then
  echo "Error: uart_checker binary not found. Build the project first." >&2
  exit 1
fi

chmod +x "$BINARY"

BUNDLE_DIR="$(dirname "$BINARY")"
exec "$BINARY" --working-dir="$BUNDLE_DIR"

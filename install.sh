#!/usr/bin/env bash
# Installs Tuck into /Applications and starts it.
# curl -fsSL https://raw.githubusercontent.com/bluejay-io/tuck/main/install.sh | bash
set -euo pipefail

REPO="bluejay-io/tuck"
URL="https://github.com/$REPO/releases/latest/download/Tuck.zip"
DEST="/Applications"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Tuck only runs on macOS." >&2
  exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 14 ]; then
  echo "Tuck needs macOS 14 (Sonoma) or newer." >&2
  exit 1
fi
if [ ! -w "$DEST" ]; then
  echo "Tuck has to live in /Applications, and this account can't write there." >&2
  echo "Ask an admin to run this command, or run it from an admin account." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Tuck..."
curl -fsSL "$URL" -o "$tmp/Tuck.zip"
ditto -x -k "$tmp/Tuck.zip" "$tmp"

if pgrep -x Tuck >/dev/null; then
  osascript -e 'quit app "Tuck"' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Tuck 2>/dev/null || true
fi

rm -rf "$DEST/Tuck.app"
mv "$tmp/Tuck.app" "$DEST/Tuck.app"
xattr -dr com.apple.quarantine "$DEST/Tuck.app" 2>/dev/null || true

open "$DEST/Tuck.app"
echo "Tuck is installed in $DEST and running. Follow the setup window to choose what to tuck."

#!/usr/bin/env bash
# Build Claude Usage.app and symlink it into ~/Applications (rebuilds
# propagate; SMAppService accepts a symlink there for Start-at-Login).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claude Usage.app"

"$SRC_DIR/scripts/build-app.sh"

mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

# Register Start at Login. Without this the app only runs until the next reboot,
# and a menu-bar app that quietly fails to come back is easy to miss for weeks.
# SMAppService can only register the calling process's own bundle, so this has
# to run the installed binary rather than call launchctl.
if "$HOME/Applications/$APP_NAME/Contents/MacOS/ClaudeUsage" --login on >/dev/null 2>&1; then
    echo "Start at Login: on"
else
    echo "Start at Login: turn it on from the menu" >&2
fi

# `open` on an already-running app just activates it, so a reinstall would
# leave the previous build running and the new one never launched — the
# symptom being an install that reports success and changes nothing.
if pkill -f "$APP_NAME/Contents/MacOS/ClaudeUsage" 2>/dev/null; then
    echo "Stopped the running instance"
    # Give launchd a moment to reap it before the replacement claims the
    # status item, otherwise both briefly sit in the bar.
    sleep 1
fi

open "$HOME/Applications/$APP_NAME"

cat <<'NOTE'

Claude Usage is now running in the menu bar.

First run
  The limits come from the "Claude Code-credentials" Keychain item, which holds
  the OAuth token this app sends to Anthropic's usage endpoint. It is read
  through /usr/bin/security, which Claude Code has already authorised, so there
  should be no password prompt — see "The Keychain" in the README for why that
  detour is what stops the prompt coming back every twelve hours.

  If the limits say "Sign-in expired", start Claude Code. Only the CLI can mint
  a fresh token; this app can only read the one it leaves behind.

Recommended, once: ../StatusItemKit/scripts/setup-signing.sh
NOTE

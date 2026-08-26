#!/bin/bash
# Build Claude Usage.app via the shared StatusItemKit bundler.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh ClaudeUsage "Claude Usage"

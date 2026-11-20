#!/bin/sh
# Starts the core from the installed app (#7). The app bundles the core's source (this folder); on each
# launch `uv sync` brings its environment in ~/Library/Application Support/Zoe/core-venv up to date with
# uv.lock (instant when nothing changed; the first run downloads Python and the dependencies, including the
# Claude Code CLI that the Agent SDK ships). Then the core replaces this shell, so the app's child is the core.
# stdout is the protocol channel: everything else goes to stderr.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SUPPORT="$HOME/Library/Application Support/Zoe"
export UV_PROJECT_ENVIRONMENT="$SUPPORT/core-venv"
export PYTHONDONTWRITEBYTECODE=1                       # never write into the signed app bundle
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  echo "Zoe needs uv to run its core: brew install uv" >&2
  exit 127
fi
mkdir -p "$SUPPORT"
uv sync --frozen --no-dev --no-editable --quiet --project "$HERE" >&2
exec "$UV_PROJECT_ENVIRONMENT/bin/zoe-core"

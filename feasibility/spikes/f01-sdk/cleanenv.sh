#!/bin/sh
# Run a command with a scrubbed environment, like a launchd-spawned app would have.
# Drops every CLAUDE_* / ANTHROPIC_* var inherited from the Claude desktop host.
exec env -i HOME="$HOME" USER="$USER" LOGNAME="$LOGNAME" SHELL="$SHELL" LANG="${LANG:-en_US.UTF-8}" \
  TMPDIR="$TMPDIR" PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$@"

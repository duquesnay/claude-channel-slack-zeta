#!/bin/bash
# Wrapper invoked by /Library/LaunchDaemons/ai.guillaume.claude-channel-slack-zeta.plist.
# Delegates to zeta-launcher.exp which handles the dev-channels prompt
# (see CLAUDE.md Gotcha #1) and the pty allocation that claude --channels needs.

set -euo pipefail

export PATH="/opt/homebrew/bin:/Users/guillaume/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="/Users/guillaume"

LOGDIR="$HOME/dev/nestor/ai-gateway-zeta/logs"
mkdir -p "$LOGDIR"

exec /usr/bin/expect -f \
  /Users/guillaume/dev/nestor/ai-gateway-zeta/scripts/zeta-launcher.exp \
  >>"$LOGDIR/channel.stdout.log" 2>>"$LOGDIR/channel.stderr.log"

#!/bin/bash
# Wrapper claude --channels plugin:slack-zeta@ai-gateway-zeta.
# Le plugin est dans le marketplace local
# ~/dev/nestor/ai-gateway-zeta/marketplace/, registered via
# `claude plugin marketplace add` puis `claude plugin install`.
# Pas besoin de --mcp-config / --dangerously-load-development-channels:
# le plugin est légitime via marketplace, comme discord.

set -euo pipefail

export PATH="/opt/homebrew/bin:/Users/guillaume/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="/Users/guillaume"

LOGDIR="$HOME/dev/nestor/ai-gateway-zeta/logs"
mkdir -p "$LOGDIR"

# pty (script -q) requis sinon claude --channels bascule en --print → crash.
# auto + allowedTools whitelist sinon classifier denyait le reply tool.
exec /usr/bin/script -q /dev/null \
  /opt/homebrew/bin/claude \
  --setting-sources user,project,local \
  --channels plugin:slack-zeta@ai-gateway-zeta \
  --name claude_of_slack \
  --permission-mode auto \
  --allowedTools "mcp__plugin_slack_zeta_slack_zeta__*" \
  >>"$LOGDIR/channel.stdout.log" 2>>"$LOGDIR/channel.stderr.log"

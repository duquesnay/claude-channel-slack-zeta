# ai-gateway-zeta — Slack channel via claude --channels custom plugin

Plugin Claude Code qui transforme une session `claude --channels` en
bot Slack répondant aux DMs (workspace `robotique-yhom`). Pattern
calqué sur `discord@claude-plugins-official` mais self-hosted.

**Statut:** spike PASS. End-to-end manuel OK (DM → bot répond).
Daemon launchd encore bloqué par prompt interactif. Voir
[`MISSION.md`](MISSION.md) pour le verdict complet et
[`CLAUDE.md`](CLAUDE.md) pour le runbook.

## Quickstart (utilisateur courant)

```bash
# 1. Lance le bot en tmux (le prompt dev-channel exige un Enter humain)
tmux new-session -d -s zeta-bot -x 200 -y 50
tmux send-keys -t zeta-bot \
  "/opt/homebrew/bin/claude --dangerously-load-development-channels plugin:slack-zeta@ai-gateway-zeta --name claude_of_slack --permission-mode auto --allowedTools 'mcp__plugin_slack_zeta_slack_zeta__*'" Enter
# 2. Attache, presse Enter sur "I am using this for local development"
tmux attach -t zeta-bot
# 3. DM le bot @claude-zeta dans Slack robotique-yhom — il répond.
```

Pour le pairing (premier DM), voir `CLAUDE.md` section "Pairing".

## Layout

```
ai-gateway-zeta/
├── README.md                         # ce fichier
├── MISSION.md                        # contexte + verdict spike
├── CLAUDE.md                         # runbook ops + gotchas
├── marketplace/                      # marketplace local (registered globally)
│   ├── .claude-plugin/
│   │   └── marketplace.json          # déclaration marketplace
│   └── external_plugins/slack-zeta/  # le plugin
│       ├── .claude-plugin/
│       │   └── plugin.json           # nom + version + meta
│       ├── server.ts                 # MCP server + Socket Mode (Slack)
│       ├── package.json              # deps: @slack/socket-mode, @slack/web-api, MCP SDK
│       ├── .mcp.json                 # spawn config pour claude code
│       └── bun.lock
├── scripts/
│   └── run-channel.sh                # wrapper LaunchDaemon (bloqué par prompt)
├── launchd/
│   └── ai.guillaume.claude-channel-slack-zeta.plist  # plist (à débloquer)
├── docs/
│   ├── slack-app-setup.md            # procédure manuelle Dev Portal
│   └── slack-app-manifest.yaml       # manifest pour création via API
└── logs/                             # logs runtime (gitignored)
```

## State externe (pas dans le repo)

| Quoi                      | Où                                                              |
| ------------------------- | --------------------------------------------------------------- |
| Bot tokens (xoxb + xapp)  | `~/.claude/channels/slack-zeta/.env` (chmod 600)                |
| Pairing / allowlist       | `~/.claude/channels/slack-zeta/access.json`                     |
| Backup tokens             | 1Password vault `nestor` (4 items pour zeta + jasquier backup) |
| Marketplace registration  | `~/.claude/settings.json` `extraKnownMarketplaces.ai-gateway-zeta` |
| Plugin install ledger     | `~/.claude/plugins/installed_plugins.json`                      |
| Logs MCP plugin           | `~/Library/Caches/claude-cli-nodejs/-Users-guillaume-dev-nestor-ai-gateway-zeta/mcp-logs-plugin-slack-zeta-slack-zeta/` |

## Flux d'un message Slack → réponse

```
User DM @claude-zeta "Yo"
    ↓ (Socket Mode WebSocket)
plugin/server.ts: messageCreate event
    ↓ gate(senderId, chatId)
allowed.allowFrom contains senderId? oui
    ↓
mcp.notification('notifications/claude/channel', {content, meta})
    ↓ (MCP stdio vers claude --channels parent)
claude reçoit <channel source="slack-zeta" chat_id="..." ...>
    ↓ (LLM réfléchit, décide de répondre)
claude calls mcp__plugin_slack_zeta_slack_zeta__reply(chat_id, text)
    ↓
plugin: slack.chat.postMessage({channel: chat_id, text})
    ↓
User voit la réponse dans Slack
```

# Setup Slack app pour zeta

À faire dans le workspace **robotique-yhom**.

## 1. Créer l'app

api.slack.com/apps → Create New App → From scratch
- Nom: `claude-zeta` (ou ce que tu veux)
- Workspace: robotique-yhom

## 2. Activer Socket Mode

App config → Socket Mode → toggle ON
- Génère un app-level token avec scope `connections:write`
- **Copie le token `xapp-...`** → c'est `SLACK_APP_TOKEN`

## 3. OAuth & Permissions (Bot scopes)

Bot Token Scopes minimum:
- `chat:write` — pour répondre
- `im:history` — pour lire les DMs
- `im:read` — métadonnées IM

Pour plus tard (channels publics):
- `channels:history`, `channels:read`, `app_mentions:read`

## 4. Event Subscriptions

App config → Event Subscriptions → toggle ON (Socket Mode coche
Socket auto, pas besoin de Request URL).
Subscribe to bot events:
- `message.im` — DMs

Pour plus tard:
- `app_mention`, `message.channels`

## 5. Install to workspace

App config → Install App → Install to robotique-yhom.
- **Copie le bot token `xoxb-...`** → c'est `SLACK_BOT_TOKEN`

## 6. Écrire les tokens

```bash
mkdir -p ~/.claude/channels/slack-zeta
cat > ~/.claude/channels/slack-zeta/.env <<'EOF'
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
EOF
chmod 600 ~/.claude/channels/slack-zeta/.env
```

## 7. Test fast (avant le LaunchDaemon)

```bash
cd ~/dev/nestor/ai-gateway-zeta/plugin
bun install
bun server.ts
```

Si tu vois `slack-zeta: socket mode connected` en stderr, le bot
est connecté. DM-le depuis Slack → tu devrais recevoir un code de
pairing en réponse.

## 8. Pair

```
/slack-zeta:access pair <code-reçu>
```

(Le skill /slack-zeta:access reste à écrire — pour le spike, on
peut éditer access.json à la main.)

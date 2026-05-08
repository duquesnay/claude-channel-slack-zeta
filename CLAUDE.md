# CLAUDE.md — ai-gateway-zeta runbook

Runbook ops du bot Slack zeta. Pour le pourquoi, voir
[`MISSION.md`](MISSION.md). Pour le quoi-c'est, voir
[`README.md`](README.md).

## Mode actuel

Bot tourne en **tmux interactive** (pas en LaunchDaemon — le prompt
de confirmation `--dangerously-load-development-channels` bloque le
mode headless, voir [Gotcha #1](#gotcha-1-prompt-dev-channels-au-boot)).

Workspace Slack: `robotique-yhom`. App: `claude-zeta`. Bot user:
`@claude-zeta` (snowflake `U0B3DEULF24`, bot_id `B0B2NQGL1J8`).

## Commande de lancement (manuel via tmux)

```bash
tmux new-session -d -s zeta-bot -x 200 -y 50
tmux send-keys -t zeta-bot \
  "/opt/homebrew/bin/claude \
    --dangerously-load-development-channels plugin:slack-zeta@ai-gateway-zeta \
    --name claude_of_slack \
    --permission-mode auto \
    --allowedTools 'mcp__plugin_slack_zeta_slack_zeta__*'" Enter
tmux attach -t zeta-bot
# Press Enter on "I am using this for local development" prompt.
```

Une fois Enter pressé, claude affiche `Listening for channel
messages from: plugin:slack-zeta@ai-gateway-zeta` et le bot reçoit
les DMs Slack.

## Setup initial (one-time)

### 1. Slack app

Voir [`docs/slack-app-setup.md`](docs/slack-app-setup.md) pour le
flux manuel ou [`docs/slack-app-manifest.yaml`](docs/slack-app-manifest.yaml)
pour création via API.

Tokens à récupérer:
- `xoxb-...` (Bot Token, OAuth Install)
- `xapp-...` (App-Level Token, Socket Mode, scope `connections:write`)

Bot scopes minimum: `chat:write`, `im:history`, `im:read`,
`reactions:write` (depuis #1, ack reaction). Bot events:
`message.im`. **Privileged Gateway Intents** Message Content: à
activer dans Dev Portal (gotcha Slack universel).

### 2. Tokens sur disque

```bash
mkdir -p ~/.claude/channels/slack-zeta
cat > ~/.claude/channels/slack-zeta/.env <<EOF
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
EOF
chmod 600 ~/.claude/channels/slack-zeta/.env
```

Backup recommandé en 1Password (vault `nestor`):
- `Slack zeta - bot token`
- `Slack zeta - app token (Socket Mode)`

### 3. Marketplace + plugin install

```bash
claude plugin marketplace add ~/dev/nestor/ai-gateway-zeta/marketplace
claude plugin install slack-zeta@ai-gateway-zeta
```

Vérifier: `claude plugin list | grep zeta` doit afficher
`enabled` (scope: user).

## Pairing (1er DM)

Première fois qu'un user envoie un DM au bot, le plugin répond avec
un code 6-char et drop le message. Approuver depuis le terminal:

```bash
# Lire le code que tu as reçu en Slack, puis:
python3 -c "
import json, os
p = os.path.expanduser('~/.claude/channels/slack-zeta/access.json')
a = json.load(open(p))
code = input('code: ').strip()
entry = a['pending'].pop(code)
a.setdefault('allowFrom', []).append(entry['senderId'])
json.dump(a, open(p, 'w'), indent=2)
print(f'paired: {entry[\"senderId\"]}')
"
```

(Le skill `/slack-zeta:access pair <code>` reste à écrire — voir
TODO en bas de [`MISSION.md`](MISSION.md).)

## Restart / Stop

```bash
# Restart: stop puis relancer la commande de lancement
tmux kill-session -t zeta-bot
# Puis re-runner la commande de lancement (avec Enter manuel sur prompt)

# Stop sans restart
tmux kill-session -t zeta-bot
```

## Logs

Trois sources, à corréler par timestamp:

```bash
# TUI claude --channels (capture le pane tmux)
tmux capture-pane -t zeta-bot -p

# MCP plugin slack-zeta (Connection / Channel notifications / inbound msgs)
ls -t ~/Library/Caches/claude-cli-nodejs/-Users-guillaume-dev-nestor-ai-gateway-zeta/mcp-logs-plugin-slack-zeta-slack-zeta/*.jsonl | head -1 | xargs tail -f

# Stderr du plugin (Socket Mode connect/error, gating decisions)
# → mêlés dans le pane tmux au stderr de claude
```

État sain dans MCP log:
```
"Successfully connected (transport: stdio)"
"Connection established with capabilities: ..."
"Channel notifications registered"   ← clé: PAS "skipped"
```

État cassé (skipped):
```
"Channel notifications skipped: plugin slack-zeta@ai-gateway-zeta is not on the approved channels allowlist"
→ tu n'as pas pressé Enter sur le prompt dev-channels, ou tu as
  oublié le flag --dangerously-load-development-channels.
```

## Gotchas

### Gotcha #1 — Prompt dev-channels au boot

`--dangerously-load-development-channels` déclenche un prompt TUI
au boot:

```
WARNING: Loading development channels
  ❯ 1. I am using this for local development
    2. Exit
Enter to confirm
```

**Avant** que ce prompt soit confirmé, **AUCUN MCP ne démarre**.
Pas même context7/playwright. C'est ce qui freeze le launchd-mode
(le pty alloué par `script -q /dev/null` ne reçoit pas l'Enter).

Workarounds possibles (pas encore implémentés):
- `expect` script qui watch "Enter to confirm" et envoie `\r`
- Persistance d'acceptance entre runs (à creuser dans le binaire)
- Tmux daemon-mode permanent (la session survit aux logout)

### Gotcha #2 — `allowedChannelPlugins` user-scope ignoré

Le user-scope `~/.claude/settings.json:allowedChannelPlugins` ne
fonctionne PAS pour les plugins custom. Le binaire claude code
lit ce gate via `pA6()` qui interroge un feature flag remote
Anthropic (`tengu_harbor_ledger`). Seul le flag CLI
`--dangerously-load-development-channels` bypasse pour dev local
(jusqu'à ce que le plugin soit officiellement allowlisté côté
Anthropic).

### Gotcha #3 — `--permission-mode auto` + `--allowedTools` requis

Sans `--allowedTools "mcp__plugin_slack_zeta_slack_zeta__*"` , le
classifier auto-mode refuse l'appel du tool `reply` (logs:
`~/.claude/logs/permissions.log` "Permission denied by auto-mode
classifier"). Symptôme côté user: bot pense pendant 20s puis
silence — la pensée s'est terminée mais le tool call est bloqué.

`--permission-mode bypassPermissions` est tentant mais **casse le
chargement des MCPs entièrement** (claude reste vivant mais sans
plugins). À ne PAS utiliser.

### Gotcha #4 — Slack `assistant` mode

Pour activer la **Messages Tab** dans le DM avec le bot (sinon le
champ chat est désactivé), il faut toggler `messages_tab_enabled:
true` dans le manifest. Sans ça l'app a un home tab vide et l'user
ne peut littéralement pas écrire au bot.

Voir [`docs/slack-app-manifest.yaml`](docs/slack-app-manifest.yaml).

## Pistes d'évolution

| Idée                              | Effort  | Notes                                                                     |
| --------------------------------- | ------- | ------------------------------------------------------------------------- |
| Auto-Enter prompt → daemon launchd | mid     | `expect` ou tmux daemon-mode persistant                                   |
| Skill `/slack-zeta:access`         | low     | Calque `/discord:access` (pair, allow, status, group)                     |
| Ack reaction inbound (:eyes:)      | low     | `reactions.add` dès message reçu, comme `ackReaction` du plugin discord  |
| Reaction de progression            | mid     | Hook sur `notifications/claude/channel/permission_request` → :hourglass: |
| Status Slack natif                 | mid     | `assistant.threads.setStatus` (besoin app `bot+assistant`)                |
| Streaming des réponses             | high    | `reply_open` / `reply_chunk` / `reply_close` + `chat.update` throttled    |
| Permission relay                   | mid     | Déjà fait dans plugin discord — port quasi 1-pour-1                       |
| Pin / unpin                        | low     | Slack `pins.add` quand claude pousse un msg "important"                   |

## Comparatif Slack jasquier vs zeta

| Aspect            | claude-channel-slack (jasquier)      | claude --channels plugin (zeta) |
| ----------------- | ------------------------------------ | -------------------------------- |
| Workspace         | GijiCosyNest                         | robotique-yhom                   |
| User Unix         | jasquier                             | guillaume                        |
| Process model     | bun daemon spawn `claude -p` par msg | claude --channels persistant     |
| Daemon            | LaunchDaemon system natif            | Tmux interactif (prompt bloque)  |
| State             | `~jasquier/.claude/channels/slack/`  | `~guillaume/.claude/channels/slack-zeta/` |
| Session continuity | sessions.json + --session-id        | Native via mémoire claude        |
| Maintenance       | Code maintenu localement             | Plugin custom (idéalement upstream Anthropic) |

Le pattern jasquier est plus mature en prod; zeta est le proof of
concept pour un futur unifié (un seul mécanisme channels pour
tous les bots).

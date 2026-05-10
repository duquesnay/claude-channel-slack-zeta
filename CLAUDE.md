# CLAUDE.md — ai-gateway-zeta runbook

Runbook ops du bot Slack zeta. Pour le pourquoi, voir
[`MISSION.md`](MISSION.md). Pour le quoi-c'est, voir
[`README.md`](README.md).

## Mode actuel

Bot tourne en **LaunchDaemon système** (`ai.guillaume.claude-channel-slack-zeta`)
via wrapper expect qui dismiss le prompt dev-channels (voir
[Gotcha #1](#gotcha-1-prompt-dev-channels-au-boot) — résolu, choix
documenté dans [`planning/decision-journal.md`](planning/decision-journal.md)).

Workspace Slack: `robotique-yhom`. App: `claude-zeta`. Bot user:
`@claude-zeta` (snowflake `U0B3DEULF24`, bot_id `B0B2NQGL1J8`).

## Restart / Stop (sous launchd)

```bash
# Restart (kickstart -k = SIGTERM puis respawn)
sudo launchctl kickstart -k system/ai.guillaume.claude-channel-slack-zeta

# Stop sans respawn (désactive jusqu'au prochain bootstrap/reboot)
sudo launchctl bootout system/ai.guillaume.claude-channel-slack-zeta

# Re-bootstrap après bootout
sudo launchctl bootstrap system /Library/LaunchDaemons/ai.guillaume.claude-channel-slack-zeta.plist

# State / PID
sudo launchctl print system/ai.guillaume.claude-channel-slack-zeta | grep -E 'state|pid|last exit'
```

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

### Gotcha #1 — Prompt dev-channels au boot (résolu)

`--dangerously-load-development-channels` déclenche un prompt TUI
au boot:

```
WARNING: Loading development channels
  ❯ 1. I am using this for local development
    2. Exit
Enter to confirm
```

**Avant** que ce prompt soit confirmé, **AUCUN MCP ne démarre**
(pas même context7/playwright). C'est ce qui freezait jadis le
launchd-mode (`script -q /dev/null` n'a pas de canal pour envoyer
l'Enter).

**Résolu (2026-05-09)**: `scripts/zeta-launcher.exp` spawn claude
dans un pty alloué par expect, sleep 3s, send `\r`, sleep 3s, send
`\r` (filet de sécurité). Voir
[`planning/decision-journal.md`](planning/decision-journal.md) pour
les alternatives écartées et signaux de revoir cette décision.

### Gotcha #2 — `allowedChannelPlugins` user-scope ignoré

Le user-scope `~/.claude/settings.json:allowedChannelPlugins` ne
fonctionne PAS pour les plugins custom. Le binaire claude code
lit ce gate via `pA6()` qui interroge un feature flag remote
Anthropic (`tengu_harbor_ledger`). Seul le flag CLI
`--dangerously-load-development-channels` bypasse pour dev local
(jusqu'à ce que le plugin soit officiellement allowlisté côté
Anthropic).

### Gotcha #3 — `--permission-mode auto` + `--allowedTools` requis

Sans `--allowedTools "mcp__plugin_slack-zeta_slack-zeta__*"` , le
classifier auto-mode refuse l'appel du tool `reply` (logs:
`~/.claude/logs/permissions.log` "Permission denied by auto-mode
classifier"). Symptôme côté user: bot pense pendant 20s puis
silence — la pensée s'est terminée mais le tool call est bloqué.

`--permission-mode bypassPermissions` est tentant mais **casse le
chargement des MCPs entièrement** (claude reste vivant mais sans
plugins). À ne PAS utiliser.

### Gotcha #5 — `--resume` + `--dangerously-load-development-channels` = bot silencieux

Combiner `--resume <session>` avec `--dangerously-load-development-channels`
provoque deux bugs cumulés:
1. **Duplication channels**: --resume restaure la session avec son
   `--channels` d'origine; --dangerously rajoute le channel à
   nouveau. TUI affiche "Listening for channel messages from:
   plugin:X@Y, plugin:X@Y" (deux fois la même chose).
2. **Session ID mismatch**: la subscription MCP s'enregistre sous
   l'ancien session ID (de la session resumée), mais claude tourne
   sous un nouveau session ID. Les notifications routées vers
   l'ancien ID disparaissent — claude ne reçoit jamais l'inbound,
   bot reste silencieux.

Symptôme: réactions/status arrivent (le bun MCP fait ça côté Slack
direct) mais aucun "← slack-zeta · ..." dans le TUI claude, pas de
réponse en Slack.

Workaround actuel: lancer **sans --resume** (perte de continuité
transcript). Le launcher.exp ne passe plus --resume depuis 2026-05-10.

Si Anthropic fixe le merge --resume + --dangerously, on pourra
restaurer --resume. Voir
[`planning/decision-journal.md`](planning/decision-journal.md)
"Drop --resume".

### Gotcha #4 — Slack `assistant` mode

Pour activer la **Messages Tab** dans le DM avec le bot (sinon le
champ chat est désactivé), il faut toggler `messages_tab_enabled:
true` dans le manifest. Sans ça l'app a un home tab vide et l'user
ne peut littéralement pas écrire au bot.

Voir [`docs/slack-app-manifest.yaml`](docs/slack-app-manifest.yaml).

## Comparatif Slack jasquier vs zeta

| Aspect            | claude-channel-slack (jasquier)      | claude --channels plugin (zeta) |
| ----------------- | ------------------------------------ | -------------------------------- |
| Workspace         | GijiCosyNest                         | robotique-yhom                   |
| User Unix         | jasquier                             | guillaume                        |
| Process model     | bun daemon spawn `claude -p` par msg | claude --channels persistant     |
| Daemon            | LaunchDaemon system natif            | LaunchDaemon system + expect launcher |
| State             | `~jasquier/.claude/channels/slack/`  | `~guillaume/.claude/channels/slack-zeta/` |
| Session continuity | sessions.json + --session-id        | Native via mémoire claude        |
| Maintenance       | Code maintenu localement             | Plugin custom (idéalement upstream Anthropic) |

Le pattern jasquier est plus mature en prod; zeta est le proof of
concept pour un futur unifié (un seul mécanisme channels pour
tous les bots).

## Project Learnings

### 2026-05-10 — Bot silencieux malgré reactions/status

**Methodological:**
- **Standalone test client comme outil de triage** quand une
  intégration est silencieuse. On a écrit un mini bun script avec
  les mêmes tokens + SDK mais aucune logique métier (juste
  `console.error` sur events reçus). Result: événements arrivaient
  bien côté Slack → le bug était entre bun MCP et claude --channels,
  pas entre Slack et bun. Sans ce test, on aurait passé une heure
  à debugger les mauvaises hypothèses (Slack-side vs notre code).
  Pattern réutilisable pour tout intégrateur avec multi-couche.

**Technical:**
- **Single-client protocols + zombies = trou noir silencieux.** Slack
  Socket Mode = un seul client par xapp- token. Quand
  `claude --channels` est restart à répétition, les anciens `bun
  server.ts` deviennent orphans (PPID=1) mais continuent à monopoliser
  la session WS. Slack délivre au plus ancien — qui n'a plus de
  parent claude qui écoute → events disparaissent. Symptôme piège:
  réactions/status fonctionnent (le vieux bun les pose côté Slack
  API directe), mais claude ne reçoit jamais la notification MCP.
  Toujours `pgrep -af "bun.*<plugin>" | wc -l` avant de conclure
  "config Slack cassée" — si > 2, kill orphans d'abord.
  Mitigation mécanisée: pkill défensif + assertion fail-fast au
  boot du `zeta-launcher.exp`.

- **`--dangerously-load-development-channels` REMPLACE `--channels`**,
  ne s'additionne pas. Avec `--resume` qui restaure le `--channels`
  de la session précédente + `--dangerously` qui rajoute, on obtient
  une duplication ("Listening for channel messages from: X, X" dans
  le TUI) ET un session ID mismatch (registration sous l'ancien ID
  de session, runtime sous le nouveau) → notifications routées vers
  une session morte. Use one or the other, never both.

**Proposed Decision Anchors:**
- **Cleanup pre-spawn dans launcher**: doit-on garder pkill
  défensif + assertion fail-fast (notre choix) ou exiger
  rotation manuelle?
- **--resume vs fresh sessions**: continuité de transcript vs
  risque de duplication channels. Choix actuel: fresh (sans
  --resume) jusqu'à ce que claude code corrige le merge --resume +
  --dangerously.

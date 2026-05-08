# Mission ζ (zeta) — Slack channel via claude --channels plugin

**Statut: PASS (2026-05-08).** End-to-end loop validé manuellement —
DM Slack → plugin gate → MCP notification → claude → reply tool →
chat.postMessage → réponse côté user. Voir [`CLAUDE.md`](CLAUDE.md)
pour le runbook + gotchas.

## Contexte

Suite epsilon (Discord, marketplace officiel Anthropic). Le but de
zeta: porter le **même pattern** `claude --channels` vers Slack avec
un **plugin custom** (workspace `robotique-yhom`), distinct du daemon
`claude-channel-slack` existant qui tourne sous `jasquier` (workspace
`GijiCosyNest`, pattern bun-spawn-`claude -p`).

## Décisions actées (et tenues)

- **Spike, pas remplacement.** Aucun engagement de retirer le
  daemon jasquier. Coexistence: workspaces différents, bot tokens
  différents.
- **Plugin emballé en marketplace local** (et non `--plugin-dir`).
  Layout: `marketplace/.claude-plugin/marketplace.json` +
  `marketplace/external_plugins/slack-zeta/{server.ts,package.json,
  .mcp.json,.claude-plugin/plugin.json}`. Installé via
  `claude plugin marketplace add` + `claude plugin install`.
- **Workspace dédié:** `robotique-yhom`. App: `claude-zeta` (créée
  via manifest API — voir `docs/slack-app-manifest.yaml`).
- **Tokens en 1Password:** vault `nestor`, items `Slack zeta - bot
  token` + `Slack zeta - app token (Socket Mode)` + `Slack config
  tokens (workspace robotique-yhom)`. Origine sur disque:
  `~/.claude/channels/slack-zeta/.env` (chmod 600).

## Hypothèses validées

1. ✓ Slack Socket Mode + claude --channels marche.
   `@slack/socket-mode` + `@slack/web-api` côté plugin, transport
   stdio MCP côté claude.
2. ✓ `notifications/claude/channel` est plateforme-agnostique. Même
   shape que dans le plugin discord officiel.
3. ✓ Whitelist `mcp__plugin_<name>_<server>__*` suffit pour le tool
   de reply (`mcp__plugin_slack_zeta_slack_zeta__*`).
4. ✓ Pairing/access.json model du plugin discord recopiable. Codes
   6-char générés côté plugin, approuvés côté terminal user.

## Hypothèse INVALIDÉE (apprentissage majeur)

**Le user-scope `~/.claude/settings.json` `allowedChannelPlugins`
est ignoré pour les plugins custom non-marketplace officiel.** Le
binaire claude code lit ce gate via `pA6()` qui interroge un feature
flag remote (`tengu_harbor_ledger`) côté Anthropic. Le seul levier
pour bypasser en dev local: `--dangerously-load-development-channels`.

Conséquence: nos 4 entrées historiques dans
`~/.claude/settings.json:allowedChannelPlugins` (vestiges de spikes
antérieurs marquetés "binaire bloque") n'ont **jamais fonctionné**.
La cause réelle: il fallait `--dangerously-load-development-channels`,
non documenté comme tel à l'époque (research preview).

## Gotcha bloquant (résolu)

`--dangerously-load-development-channels plugin:<name>@<marketplace>`
déclenche un prompt TUI au boot:

```
WARNING: Loading development channels
  ❯ 1. I am using this for local development
    2. Exit
Enter to confirm
```

Sans Enter pressé (ou stdin TTY), claude **freeze avant tout
chargement MCP**. C'est pour ça que la version daemon launchd
(`script -q /dev/null` + KeepAlive) ne marche pas — le prompt
n'est jamais acquitté. Solution actuelle: lancer en tmux pane
manuellement, presser Enter une fois. À automatiser avec `expect`
pour daemon launchd futur.

## Tradeoffs réels (post-spike)

| Aspect            | claude-channel-slack (jasquier)      | claude --channels plugin (zeta) |
| ----------------- | ------------------------------------ | -------------------------------- |
| Process model     | bun daemon spawn `claude -p` par msg | claude --channels persistant     |
| Context           | Fresh par message (résilient inj.)   | Session continue (continuité)    |
| Crash blast       | Un msg perdu                         | Toute la session HS              |
| Coût session      | Spawn par message (latence + API)    | Session unique (cache prompt)    |
| Continuité conv   | Via --session-id JSON                | Native via mémoire claude        |
| Empreinte mémoire | Faible (process court)               | Lourde (claude reste up)         |
| Daemon launchd    | OK natif (script standalone)         | Bloqué (prompt interactif)       |

Le pattern channels-natif est plus élégant pour la conversation
continue, mais le daemon-mode launchd reste à débloquer.

## Risques persistants

- **Prompt injection long-running.** Session claude continue
  embarque l'historique. Mitigation: pairing strict (déjà actif),
  reset session périodique (à implémenter).
- **Daemon nécessite Enter au boot.** Tant que pas auto-press,
  zeta dépend d'un humain qui démarre. Acceptable pour spike,
  bloquant pour prod.
- **Maintenance plugin.** Upstream Anthropic = idéal long-terme
  (security review). Hors-scope spike.

## Évolutions identifiées (post-spike)

- [ ] Auto-Enter du prompt dev-channels pour daemon launchd
      (`expect` ou tmux daemon-mode)
- [ ] Skill `/slack-zeta:access` (équivalent `/discord:access`)
- [ ] Ack reaction inbound (:eyes: ou :thinking_face:)
- [ ] Reaction de progression (hooks sur permission_request)
- [ ] Status Slack natif (assistant.threads.setStatus)
- [ ] Streaming des réponses (chunk via chat.update)

Voir [`CLAUDE.md`](CLAUDE.md) section "Pistes d'évolution" pour les
détails techniques.

# Decision Journal — ai-gateway-zeta

PDCA-style log of design choices that have non-obvious trade-offs.
Each entry: context, decision, alternatives weighed, revisit signals.

---

## 2026-05-09 — Auto-restart via expect launcher (LaunchDaemon)

**Status**: tentative (1-2 weeks observation window)

**Context**: Bot tournait en tmux interactive parce que
`--dangerously-load-development-channels` déclenche un prompt TUI au boot
qui bloque le mode headless (Gotcha #1 dans CLAUDE.md). Coût: bot meurt
si tmux session perdue, pas d'auto-restart sur crash, pas de respawn
après reboot tanuki.

**Décision**: launcher `scripts/zeta-launcher.exp` (Tcl/expect) qui
spawn claude dans un pty et envoie 2× `\r` espacés (3s, 6s) pour
dismiss le prompt aveuglément. Lancé par
`/Library/LaunchDaemons/ai.guillaume.claude-channel-slack-zeta.plist`
via `scripts/run-channel.sh`. KeepAlive=true → respawn auto au crash;
ThrottleInterval=30s anti-thrashing.

**Alternatives écartées**:
- **Tmux daemon-mode persistant**: attachable pour debug live, mais
  wrapper plus complexe (poll loop pour signaler la mort à launchd
  qui ne peut pas watch tmux directement) et logs verbeux (ANSI codes).
- **Persistance d'acceptance dans le binaire claude**: feature inexistante
  (le flag `dangerously-load` est by design une safety gate à chaque run).
- **Plugin officiellement allowlisté Anthropic** (`tengu_harbor_ledger`):
  pas accessible — l'allowlist est un feature flag remote contrôlé côté
  Anthropic.

**Revisit signals** (déclencheraient un retour à tmux ou autre):
- Le prompt TUI change de wording/timing → 2× sends aveugles ne suffisent
  plus → besoin de matcher du texte ou attacher pour debugger
- Crash récurrent qui exige introspection live (logs ne suffisent pas)
- Besoin d'attacher pour répondre à un nouveau prompt mid-session

**Coût de revoir**: faible. Remplacer `run-channel.sh` par un wrapper
tmux qui poll, garder la même plist. ~30min.

**Owner**: guillaume. **Last review**: 2026-05-09.

---

## 2026-05-10 — pkill défensif + fail-fast assertion dans launcher

**Status**: Active

**Problem**: Restarts répétés du daemon claude --channels accumulaient
des bun MCP server.ts orphans (PPID=1 après mort du parent claude),
qui monopolisaient la session Slack Socket Mode (single-client par
xapp- token). Slack délivrait au plus ancien encore vivant — sans
parent claude pour consommer les notifications MCP → events
disparaissaient. Symptôme piège: réactions/status fonctionnaient
(le vieux bun les posait via Slack API directe) mais claude ne
recevait jamais l'inbound.

**Root Cause**: `launchctl bootout` puis `bootstrap` ne nettoient pas
les processus enfants spawnés par claude (les MCP plugins). Chaque
cycle laisse un fantôme. Le pattern claude --channels avec un MCP
qui maintient une connexion stateful externe (WebSocket Slack)
expose ce problème — pas spécifique à zeta.

**Counter-measure**: Dans `scripts/zeta-launcher.exp`:
1. `pkill -f "bun.*ai-gateway-zeta/marketplace/external_plugins/slack-zeta"`
   avant `spawn` → kill les orphans
2. Assertion fail-fast: si `pgrep | wc -l > 0` après pkill (race ou
   permission), `exit 1` → launchd KeepAlive respawn dans 30s plutôt
   que démarrer un silent-bot

**Alternatives écartées**:
- **Vérification dans server.ts** (process-local) au boot: portable
  mais pas effective si le bun précédent est figé sans recevoir
  de signaux (garbage collection bloqué). Le pkill SIGTERM externe
  est plus fiable.
- **Soft cleanup via PID file**: server.ts écrit son PID à start, le
  retire à exit. Robuste si exit gracieux, mais les zombies ici sont
  des morts brutaux (claude crash) → fichier PID stale.
- **Laisser launchd faire**: pas applicable, launchd ne tracke pas
  les enfants spawned par ses workloads.

**Pattern réutilisable** pour autres plugins claude --channels avec
MCP stateful (Discord epsilon n'est PAS concerné car Anthropic-managed,
mais tout futur plugin custom qui maintient une connexion externe).
Le pattern serait à upstream chez Anthropic ou packager comme
`channels-launcher` skill.

**Prediction**: Plus de "bot silencieux" post-restart. Si fail-fast
trigger (survivors > 0 post-pkill), ça apparaîtra dans
`logs/channel.stderr.log` avec le message clair "orphan bun MCP
survived pkill". Diagnostic facile.

**Revisit signals**:
- Si fail-fast trigger souvent (>1×/jour) → enquêter pourquoi pkill
  rate (race avec launchd? permission? bun unkillable?)
- Si Anthropic upstream un cleanup natif → retirer notre pkill
- Si zombies réapparaissent malgré pkill → switch vers SIGKILL au
  lieu de SIGTERM par défaut

**Coût de revoir**: faible. Le pkill+fail-fast est isolé dans le
launcher, ~10 lignes. Suppression triviale.

**Owner**: guillaume. **Commit**: 314a65e.

---

## 2026-05-10 — Drop --resume (perte de continuité transcript)

**Status**: Active

**Problem**: La combinaison `claude --resume <session>
--dangerously-load-development-channels plugin:X@Y` provoquait deux
bugs cumulés qui rendaient le bot silencieux malgré des réactions
Slack qui arrivaient (👀, status):
1. **Duplication de channel registration** — TUI affichait
   "Listening for channel messages from: plugin:X@Y, plugin:X@Y"
2. **Session ID mismatch** — MCP subscription enregistrée sous
   l'ancien session ID (resume), mais claude tournait sous un
   nouveau ID. Notifications routées vers session morte → trou noir.

**Root Cause**: Side effect de comment claude code merge `--resume`
(qui restaure les flags d'origine, dont `--channels`) avec
`--dangerously-load-development-channels` (qui ajoute le même
channel en mode dev). Pas de désambiguation côté claude code; les
deux entries cohabitent et le routing notification favorise la
mauvaise.

**Counter-measure**: Retirer `--resume claude_of_slack` du
`scripts/zeta-launcher.exp`. Chaque restart commence avec une
session fresh — perte de continuité transcript Slack-side, mais
les messages Slack eux-mêmes restent dans l'historique côté
Slack (rien perdu pour l'utilisateur final, juste le contexte
interne de claude qui repart à zéro).

**Alternatives écartées**:
- **Custom session-id stable**: passer `--session-id <uuid>` fixe
  pour avoir un ID prévisible. Possible mais ne résout pas la
  duplication channel (--resume ferait toujours la double-reg).
- **Merger en aval avec --fork-session**: --fork-session crée un
  nouveau ID en gardant le transcript. Pourrait éviter le
  mismatch mais doc dit "use with --resume" — on n'a pas testé.
  À explorer si on a un besoin urgent de continuité.
- **Patch upstream claude code**: la bonne solution mais hors-scope
  (pas notre repo).

**Pattern réutilisable**: Tout futur plugin claude --channels en
dev mode (--dangerously-load-development-channels) devrait éviter
--resume jusqu'à fix upstream.

**Prediction**: Bot opérationnel à chaque restart sans intervention.
Conversation Slack sans "mémoire" entre sessions claude — chaque
restart, le bot ne se souvient pas des échanges précédents (mais
peut relire l'historique Slack via fetch_messages s'il existe un
tel tool).

**Revisit signals**:
- Anthropic ship un fix --resume + --dangerously (changelog claude code)
- Besoin utilisateur explicite de continuité contextuelle inter-restart
- Tests confirment que --fork-session contourne le bug

**Coût de revoir**: trivial. Re-ajouter `--resume claude_of_slack`
en première ligne du `spawn` dans launcher.exp.

**Owner**: guillaume. **Commit**: à venir.

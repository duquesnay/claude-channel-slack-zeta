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

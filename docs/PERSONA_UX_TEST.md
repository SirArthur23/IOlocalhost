# Persona UX Test — IO: localhost

A structured walkthrough of the app's flows from the point of view of three distinct users.
Each finding is grounded in the actual implementation. Severity: 🔴 blocker · 🟠 should-fix ·
🟡 nice-to-have · ✅ works well.

> **Method note:** this is a heuristic walkthrough against the real code paths, not an
> automated GUI test. The underlying logic (detection, scanning, launch, group-kill,
> log capture) was exercised headlessly and passed; the findings below are about the
> *experience* those paths add up to.

---

## Persona 1 — Maya, senior frontend engineer

**Profile.** Lives in JS. Half a dozen Vite/Next apps, pnpm everywhere, keyboard-driven,
low tolerance for clutter. Runs `pnpm dev`, forgets which port, has 4 tabs fighting over 3000.

**Journey.** Opens app → New Server → picks a Vite repo → starts it → stars it → later stops it.

- ✅ Detection nails it: "Vite · pnpm" → `pnpm dev`, port 5173, with her `package.json`
  scripts as chips. This is exactly the "which command?" pain, solved.
- ✅ The port-in-use warning fires when 5173 is taken and names the process — saves the
  classic "address already in use" dance.
- ✅ Live logs mean she doesn't need a spare terminal tab.
- 🟠 **Quit orphans her servers.** If she ⌘Q with a dev server running, IO exits but the
  server keeps running, detached. Reopening shows it in the Running list (stoppable), but
  the silent orphan is surprising and can leave stray `node` processes running for hours.
  *Fix: on quit with managed servers running, ask "Stop N running servers / Leave running".*
- 🟡 **No Restart.** Restarting after a config/env change is Stop → wait → Start. A single
  **Restart** action on running rows would match how often frontend devs bounce a server.
- 🟡 **First-run noise.** Her very first open shows ~15–20 rows (Docker, system daemons).
  Grouping + collapsed non-dev groups mitigate it, but a one-line "these are grouped by app;
  your dev servers are green" hint on first run would orient her faster.

**Verdict.** Delightful for the core loop. The orphan-on-quit is the one thing that would
generate a "wait, why is 5173 still up?" moment.

---

## Persona 2 — Jonas, designer-developer running Ghost

**Profile.** Runs several local Ghost sites for client work. Comfortable in a GUI, *not*
comfortable in the terminal. Starts sites with a script someone set up for him
(`./ops/start_ghost_hub_local.sh`) and honestly isn't sure what it does.

**Journey.** New Server → picks his multi-site repo → needs to start the "hub" Ghost site.

- ✅ The whole reason this persona exists: detection now recognizes the `ops/` script repo
  as "Ghost project · ops scripts" and lists every start/run script as a chip with the
  correct per-site port. Before, this folder was mis-detected as a static site.
- ✅ Picking the `run_ghost_hub_local` chip fills the command **and** the right port (2370).
- 🟠 **`start_` vs `run_` is a trap for exactly this persona.** Jonas's muscle memory is the
  `start_` script — but those background/detach via `nohup`, so IO can start them and then
  can't stop or log them. IO sorts `run_*` first and the manual explains it, but a
  terminal-shy user will likely click the familiar `start_` chip and be confused when the
  log says "exited" while the site is up. *Fix: detect `nohup`/`&` in a script and either
  hide it, badge it ("backgrounds — not managed"), or auto-rewrite to the sibling `run_`.*
- 🟠 **A failed start is invisible unless he opens the log.** If `ghost run` errors (missing
  DB, wrong Node), the row just sits at "not running". This persona won't think to open the
  terminal-icon console. *Fix: surface a failure badge on the row ("exited — view log") when
  a just-launched server dies within a few seconds.*
- ✅ Once configured, the favorite starts with one click — which is the whole promise for him.

**Verdict.** The feature he asked for works. The remaining risk is that he picks the wrong
(backgrounding) script and has no obvious signal that it went sideways.

---

## Persona 3 — Priya, backend / DevOps polyglot

**Profile.** Django API, a Go service, Postgres and Redis in Docker, occasional Rust. Ten+
ports at any time. Her #1 fear: fat-fingering a kill on Postgres or a system daemon.

**Journey.** Opens app to audit what's running → stops a stray dev server → starts a Django app.

- ✅ Smart groups are the hero here: Docker's ports collapse under **Docker**, her dev
  servers under **Development** (green), Postgres flags **Application** (blue), system stuff
  **System** (orange). The confirm-before-stop on non-dev is exactly the guardrail she wants.
- ✅ Full command lines on every row (with copy) let her tell two `python` processes apart.
- ✅ Django detection → `python3 manage.py runserver 0.0.0.0:8000`; Go → `go run .`. Custom
  command mode covers the long tail.
- 🟠 **No pre-start port check from Favorites/Recent.** New Server warns about a busy port,
  but hitting **Start** on a saved Django app whose port is taken just fails into the log.
  *Fix: reuse `PortInUseNotice`/the same check on saved-row Start.*
- 🟡 **Quit orphans many servers.** Same root issue as Maya, amplified — she may have several
  managed servers; quitting leaves them all running untracked.
- 🟡 **Docker "Application" vs "System".** She might argue Docker infra is "System". Minor —
  the classifier is a hand-list and easy to tune; not wrong, just opinionated.
- 🟡 **Refresh cost.** Every 4s runs `lsof` + `ps -axww`. Fine on her machine, but on a busy
  box a slightly longer default interval (or pause-when-unfocused) would be tidier.

**Verdict.** The safety model lands well for a cautious ops user. Gaps are about parity
(port warning everywhere) and polish (quit, refresh), not correctness.

---

## Consolidated findings (ranked)

| # | Finding | Severity | Personas |
|---|---|---|---|
| 1 | Quitting the app orphans managed servers with no prompt | 🟠 should-fix | Maya, Priya |
| 2 | Icon-only buttons (star/tag/terminal/open) have no VoiceOver labels | 🟠 should-fix (a11y) | all |
| 3 | `start_*` scripts that background/detach can be launched but not managed | 🟠 should-fix | Jonas |
| 4 | A launched server that dies immediately gives no row-level signal | 🟠 should-fix | Jonas |
| 5 | No port-in-use warning on Favorites/Recent **Start** | 🟡 | Priya |
| 6 | No **Restart** action | 🟡 | Maya |
| 7 | First-run orientation hint for the Running list | 🟡 | Maya |
| 8 | Refresh interval fixed at 4s; no pause-when-unfocused | 🟡 | Priya |

## Recommended before a public v1

**Code (small, high-leverage) — done:**
- [x] #1 Confirm-on-quit when managed servers are running (stop all / leave).
- [x] #2 Add `accessibilityLabel` to icon-only buttons.
- [x] #3 Flag/handle backgrounding (`nohup … &`) start scripts (dropped when a foreground
      `run_*` sibling exists; badged otherwise).
- [x] #4 Row "exited on launch — view log" badge when a just-started server dies fast.

**Ship-readiness (non-code):**
- [x] LICENSE (MIT), release guide (`docs/RELEASE.md`), CHANGELOG.
- [ ] Gatekeeper: shipping unsigned for now (right-click / "Open Anyway"); notarize later.
- [ ] A couple of screenshots in the README, and a Releases build.

Remaining items are packaging, not product — the core tested well for all three personas.

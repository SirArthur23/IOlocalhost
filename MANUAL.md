# IO: localhost — User Manual

A friendly walkthrough of everything the app does.

- [First launch & Gatekeeper](#first-launch--gatekeeper)
- [The window](#the-window)
- [Running servers](#running-servers)
- [Smart groups & safety colors](#smart-groups--safety-colors)
- [Custom labels](#custom-labels)
- [Favorites & Recent](#favorites--recent)
- [Starting a new server](#starting-a-new-server)
- [Live logs](#live-logs)
- [Set Up / relaunching a favorite](#set-up--relaunching-a-favorite)
- [Ghost sites](#ghost-sites)
- [FAQ & troubleshooting](#faq--troubleshooting)

---

## First launch & Gatekeeper

If you downloaded a release build and macOS says *"IO: localhost cannot be opened because
the developer cannot be verified"*:

- **macOS 15 Sequoia and later:** open **System Settings → Privacy & Security**, scroll down
  to the message about IO: localhost being blocked, and click **Open Anyway**.
- **Older macOS:** right-click (Control-click) the app in Finder → **Open** → **Open**.

You only need to do this once. (Notarized builds skip this step entirely.)

## The window

The sidebar has a prominent **＋ New Server** button and three sections:

| Section | What it shows |
|---|---|
| **Running** | Every process currently listening on a local TCP port |
| **Favorites** | Servers you've starred |
| **Recent** | Servers you've started from a folder, newest first |

The number next to each section is a live count.

## Running servers

The **Running** list refreshes every few seconds. Each row shows the port, the process,
its PID, address, and the full command line. Buttons on each row:

- **☆ Star** — add to Favorites (captures how to relaunch it, when possible).
- **🏷️ Tag** — give the port a custom label.
- **🧭 Open** — open `http://localhost:<port>` in your browser.
- **⏹ Stop** — stop the process.

Right-click a row for **Open in Browser**, **Set Label…**, **Copy Command Line**, and **Stop**.

## Smart groups & safety colors

Ports are grouped by the app they belong to — all of Docker's ports under **Docker**, all of
Adobe's under **Adobe**, your dev servers under **Development**, and so on. Each group is
tagged and color-coded:

- 🟢 **Development** — your dev servers. Safe to stop.
- 🔵 **Application** — third-party apps (Adobe, Docker, databases…). Stop with care.
- 🟠 **System** — macOS background services. Don't stop these.
- ⚪ **Other** — unclassified.

Your **Development** group is expanded by default; the noisier groups are collapsed. If you
try to stop anything that isn't a dev server, IO asks for confirmation first, so you can't
kill Docker or a system service by reflex.

## Custom labels

Ports and PIDs are precise but not memorable. Click the **🏷️ tag** button on a running row
(or **Rename…** on a saved one) to give a server a name like *"Marketing site"*. Labels
stick to the port and persist.

## Favorites & Recent

- Click the **☆** on any server — running or saved — to pin it to **Favorites**.
- Servers you start from a folder appear in **Recent**, newest first, ready to relaunch.

On a favorite/recent row, a green dot means it's currently running. You'll see **Start**,
**Stop**, a **Set Up…** button (if IO doesn't yet know how to launch it), and a **⋯** menu
with Rename, Edit Launch Settings, Open in Browser, Reveal in Finder, and Remove.

## Starting a new server

1. Click **＋ New Server**.
2. Click **Choose…** and pick your project folder.
3. IO shows a **Detected** panel — the project type, package manager, and the exact command
   it will run. For Node projects, your `package.json` scripts appear as clickable chips.
4. Pick **Built-in method** or **Custom command** (IO preselects the best guess).
5. Give it a label, confirm the port, and press **Create Server**.

If the chosen port is already in use, IO warns you before you start and names the process
that's holding it.

## Live logs

Anything you start from IO streams its output into a **log console** — click the **terminal
icon** on the server's row. The console shows the command, live output, and a running/stopped
indicator, with **Clear**, **Copy**, and **Start/Stop**. Logs are saved to disk and restored
the next time you open the app.

## Set Up / relaunching a favorite

When you favorite a server that IO didn't start (say, one launched by a script or another
tool), it tries to capture how to relaunch it. Some servers — notably Node/Next/Vite — hide
their original command, so IO can't always recover it. In that case the favorite shows a
**Set Up…** button:

1. Click **Set Up…**.
2. Point it at the project folder.
3. Choose a built-in method **or** type the exact command you use.
4. **Save & Start** (or just Save).

From then on, that favorite starts with one click.

## Ghost sites

IO detects Ghost in two forms:

- **Ghost-CLI installs** (a folder with `.ghost-cli`) → runs `ghost run --development`.
- **Custom ops scripts** — repos that start Ghost via `ops/`, `scripts/`, or `bin/` shell
  scripts (e.g. `start_<site>_local.sh`, `run_<site>_local.sh`). IO lists every start-like
  script as a chip and reads the correct port from the script or the Ghost config it points at.

**Use the `run_*` script chips**, not `start_*`. The `run_*` variants run Ghost in the
foreground, so IO can manage them fully (stop, live logs). The `start_*` variants background
Ghost and detach it — IO can start them, but can't track or stop them afterwards.

## FAQ & troubleshooting

**A server won't start / exits immediately.**
Open its log console (terminal icon). The error is almost always there — a missing tool, a
wrong command, or a port already in use. Fix it via **Set Up… / Edit Launch Settings**.

**I quit the app while a server was running — what happens?**
Servers you started keep running in the background. Reopen IO and you'll see them in the
Running list; you can stop them there.

**A group is labeled "Other" but it's actually a known app.**
The classifier uses a built-in list. It's easy to extend — open an issue with the process
name and what it should be called.

**The port I want is taken.**
The New Server / Set Up forms warn you and name the process using it. Stop that process first,
or pick another port.

**Does it work with pnpm / yarn / bun?**
Yes — IO reads your lockfile and suggests the matching command (`pnpm dev`, `yarn dev`, …).

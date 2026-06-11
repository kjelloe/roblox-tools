# Roblox Studio Development Workspace

Tooling for developing Roblox Studio plugins (currently the **MultiAnimation**
animation plugin) with a fast, scriptable workflow: live code execution in
Studio, hot-reload on save, automated tests, AI asset generation, and
git-friendly animation data — all driven from the WSL terminal or Claude Code.

Everything talks to a running Roblox Studio through the Studio MCP server
(`StudioMCP.exe`), so **Studio must be open with the place loaded** for most
commands to work.

---

## One-Time Setup

1. Open Roblox Studio and load `MultiAnimation/MultiAnim.rbxl`
   (the MCP plugin must be active in Studio's Plugins tab).
2. The `mcp` alias should point at the repo's helper:
   ```bash
   alias mcp="python3 ~/GIT/Roblox/mcp.py"   # already in ~/.bashrc
   ```
3. Smoke test:
   ```bash
   mcp state          # → "Current Studio Mode: Edit"
   ```
   The first call auto-starts a background daemon that keeps the Studio
   connection warm — after that every command answers in well under a second.

---

## Daily Plugin Development

The fastest loop is **devsync** — edit a `.lua` file, save, and the plugin
reloads inside Studio in ~0.4 s. No Studio restart, no clicking.

```bash
cd MultiAnimation
python3 devsync.py install     # once; then restart Studio one time
python3 devsync.py             # watch mode — every save hot-reloads
# ... edit plugin/**.lua, save, watch Studio update live ...
python3 devsync.py uninstall   # back to the classic workflow when done
```

Every save is compile-checked in Studio first — syntax errors are printed with
line numbers and the reload is skipped until you fix them.

**Classic workflow** (no dev loader installed):

```bash
python3 build.py               # build + install the .rbxmx
# then in Studio: Plugins → Manage Plugins → reload MultiAnimation
python3 watch.py               # or: auto-build on every save
```

---

## Testing

```bash
mcp test                 # full suite — 164 cases, ~0.7s
mcp test prop            # only tests matching *prop*
mcp test ui -v           # UI integration tests, verbose
mcp playtest             # play-mode test: deploys, presses F5, watches the
                         # console for FINISHED/ERROR, exits play mode, reports
```

The suite runs **against the live Studio session** — including 18 UI tests that
drive the actual plugin panel (rig selection, timeline, keyframes) through a
test bridge. Tests clean up after themselves.

---

## Running Code & Inspecting Studio

```bash
mcp luau "return workspace.Name"          # run any Lua, get the result back
mcp luau -f some/script.lua               # run a file
mcp console MultiAnimation                # read Studio output (filtered)
mcp tail MultiAnimation                   # live-tail the output window
mcp tree workspace.FIGURES                # browse the instance tree
mcp inspect workspace.FIGURES.Rig1.Torso.Neck   # properties of one instance
mcp read game.ServerStorage.MultiAnimationData.MultiAnimPlayer   # script source
mcp grep "RegisterKeyframeSequence"       # search all script contents
mcp capture                               # screenshot the viewport
```

---

## Keeping Code in Sync

```bash
mcp check plugin/core/Exporter.lua   # compile-check a file in Studio (no execution)
mcp drift                            # is ServerStorage's MultiAnimPlayer stale
                                     # compared to game/MultiAnimPlayer.lua?
mcp deploy                           # push the local MultiAnimPlayer to ServerStorage
```

`mcp drift` exists because "I rewrote the module but the old version is still
deployed" has actually happened — run it whenever playback behaves like your
changes didn't land.

---

## Animation Data in Git

Exported scenes (keyframes, scale/root/prop tracks) normally live only inside
the binary `.rbxl`. `mcp scene` turns them into diffable text under
`MultiAnimation/scenes/`:

```bash
mcp scene list                     # what's in Studio vs what's on disk
mcp scene pull Scene_001           # Studio → scenes/Scene_001/*.json + *.lua
mcp scene push Scene_001           # disk → Studio (rebuilds the scene folder)
mcp scene push Scene_001 --as Scene_001_backup
```

Pull after every animation session you care about, and commit. The round-trip
is lossless.

---

## Creating Assets

```bash
mcp gen model "a wooden crate with adjustable size" --wait   # AI model → workspace
mcp gen mesh "medieval sword" --size 1,4,0.3 --tris 5000     # AI textured mesh
mcp gen material "rough mossy stone" --base Rock --pattern Organic
mcp store "low poly tree"                  # search the Creator Store
mcp store "low poly tree" --insert         # ...and insert the best match
mcp addrig                                 # clone Rig1 → Rig3 (the plugin
                                           # auto-detects it immediately)
```

`gen model` is asynchronous — without `--wait` it prints a generation ID you
can await later with `mcp gen wait <id>`.

---

## The Daemon (why everything is fast)

Every `mcp` command needs a `StudioMCP.exe` proxy. Spawning one per call costs
5–10 s; the daemon keeps one alive behind a Unix socket so calls take ~0.07 s.

You normally never think about it — it **auto-starts on first use**. Manual
control if needed:

```bash
mcp daemon status | start | stop
MCP_NO_DAEMON=1 mcp state        # bypass it for one command
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no Studio instance connected` | Open Studio with the place loaded; check the MCP plugin is on |
| Commands slow again | `mcp daemon status` — restart with `mcp daemon stop && mcp daemon start` |
| Playback ignores code changes | `mcp drift`, then `mcp deploy` |
| devsync push fails after Studio restart | Just retry — the daemon re-primes itself |
| Plugin panel gone after hot-reload error | Fix the error, save again — the loader reboots on every push |
| Weird rig pose left over from tests | Plugin reconnects motors on unload; or restart the plugin |

---

## Repository Map

| Path | What |
|---|---|
| `mcp.py` | The `mcp` CLI — every subcommand listed above (`mcp --help`) |
| `MultiAnimation/` | The animation plugin: source, tests, build & dev scripts |
| `MultiAnimation/DEV_TOOLS.md` | Full documentation for every dev tool |
| `MultiAnimation/SPEC.md` / `ARCHITECTURE.md` / `DATA_FORMAT.md` / `PHASES.md` | Plugin spec, design, data formats, roadmap |
| `MultiAnimation/scenes/` | Version-controlled animation data (`mcp scene`) |
| `ROBLOX_MCP_TOOLS.md` | Reference for the raw Studio MCP tools |
| `CLAUDE.md` | Instructions for Claude Code sessions in this repo |

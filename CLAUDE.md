# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workflow — Rojo sync, NOT direct Studio edits

Lua scripts live in `src/` on disk and are pushed to Roblox Studio via Rojo. The authoritative copy is on disk.

- `rojo serve` — start sync server on port 34872. Run from project root before opening Studio.
- In Studio: Plugins → Rojo → **Connect**. After this, every save of a `src/**.lua` file is mirrored into Studio in real time.
- `rojo build -o build.rbxlx` — export `src/` to a place file without Studio (CI / sanity-check builds).

**Do NOT edit Lua scripts via the Roblox Studio MCP.** Disk is the source of truth — MCP edits to scripts go stale immediately when the next disk save fires. Use `Edit`/`Write` on `src/*.lua`. Workspace instances (parts, models, attributes, tags) that don't have a disk representation can still be inspected and modified through the MCP / `execute_luau`.

## Rojo file-name → instance-class mapping

`default.project.json` maps four directories one-for-one to Roblox services. The suffix decides the instance class:

| Disk path | In Studio | File suffix → class |
|---|---|---|
| `src/ServerScriptService/` | ServerScriptService | `*.server.lua` → `Script` |
| `src/ServerStorage/` | ServerStorage | `*.lua` → `ModuleScript` |
| `src/ReplicatedStorage/` | ReplicatedStorage | `*.lua` → `ModuleScript` |
| `src/StarterPlayerScripts/` | StarterPlayer.StarterPlayerScripts | `*.client.lua` → `LocalScript` |

`$ignoreUnknownInstances: true` is set on every service — instances created at runtime (RemoteEvents, BindableEvents, leaderstats folders, template clones) live only in the `.rbxl` and don't conflict with the Rojo tree.

## What's NOT in git

The `.rbxl` Studio file holds all big assets — large diffs would be useless on binaries:

- `Workspace` — mazes, bases (`bazapl1`–`bazapl4`), `BrainrotSpawnPad` parts, trap models with their attributes.
- `ServerStorage.BrainrotTemplates` — brainrot models (with meshes), each tagged with a `Rarity` attribute.
- `ServerStorage.TrapTemplates`, `ServerStorage.BrainrotEvents` — created/populated by scripts at first run.
- `ReplicatedStorage` RemoteEvents (`DropBrainrot`, `PurchaseUpgrade`) — lazy-created by their owning server scripts on startup.

When reasoning about runtime behavior, remember that scripts often look up these instances with `WaitForChild` or create them if missing — they will not appear in `src/` on disk.

## Architecture — high-level data flow

The core gameplay is a per-player carry/deliver loop. Several scripts coordinate through tags, attributes, and BindableEvents rather than direct calls.

**Pickup → carry → deliver loop:**
1. `BrainrotSpawner` clones a model from `ServerStorage.BrainrotTemplates` onto each `BrainrotSpawnPad`-tagged part, picking a template whose `Rarity` matches the pad's `Rarities` CSV attribute. It tags the clone `Brainrot` and waits for a lifecycle event to free the pad and respawn after 30–90s.
2. `BrainrotPickup` binds `ProximityPrompt.Triggered` on every `Brainrot`-tagged model. On trigger, it welds the model above the player's head (stacked if `carryLvl > 1`), sets `player.CarryingBrainrot = true`, and fires the `Picked` BindableEvent.
3. The client (`BrainrotInput`) reads the `CarryingBrainrot` attribute to show a HUD hint and lets `E` drop the top brainrot via the `DropBrainrot` RemoteEvent.
4. `BrainrotDelivery` listens for `Touched` on all four base parts (`bazapl1`–`bazapl4`). If the toucher is the base's `Owner` and is carrying, it places the brainrot on the base, fires `Placed`, and the per-second income tick begins crediting `leaderstats.Coins`.

**Lifecycle BindableEvents** (in `ServerStorage.BrainrotEvents`): `Picked`, `Dropped`, `Placed`, `Destroyed`, `TrapHit`. The spawner subscribes to `Picked`/`Placed`/`Destroyed` to free its pad. `BrainrotPickup` subscribes to `TrapHit` to drop everything the player is carrying. New systems hook into this bus rather than calling pickup/delivery directly.

**Shared mutable state — `ServerStorage/BrainrotState.lua`** is the single source of truth for "who is carrying what." It's a stack (top = last picked up) and is consulted/mutated by both pickup and delivery. Don't shadow it with parallel state in new scripts.

**Per-player data — `ServerStorage/PlayerData.lua`** is currently in-memory only (DataStore persistence is a backlog task). `UpgradeService` reads `speedLvl` / `carryLvl` / `baseLvl`, looks up effects in `ReplicatedStorage/UpgradeConfig.lua`, and applies them: WalkSpeed on the Humanoid, `Capacity` attribute on the player's base, and `getMaxCarry` consulted by `BrainrotPickup` on every pickup attempt. It also mirrors levels to player attributes so `ShopClient` can render without server round-trips.

**Tag-driven binding** (CollectionService): `Brainrot`, `BrainrotSpawnPad`, `MazeTrap`, `TrapHitbox`, `PlacedBrainrot`. Every script that consumes a tag also subscribes to `GetInstanceAddedSignal` so manually-placed instances in Studio are picked up live. `BrainrotTagger` is a safety-net: any model in `Workspace` whose name contains "brainrot" gets the tag automatically (the user/son sometimes drops models in by hand).

**Traps — `MazeTrapsServer`** binds every `MazeTrap`-tagged model. Effective period is scaled by the maze's `Tier` attribute (Tier 1 = ×1.5 slower for tutorial, Tier 2 = baseline, +20% per tier above). On hit it fires the `TrapHit` BindableEvent — it does not directly mutate carry state.

## Conventions baked into existing scripts

- **Lazy-create RemoteEvents** with `FindFirstChild` + create-if-missing. Don't assume they exist; the script that owns them creates them on startup.
- **Attribute-based config on Workspace instances**: pad `Rarities` (CSV), maze `Tier`, trap `Period` / `ActiveDuration` / `TrapType`, base `Owner` / `Capacity`. Tuning gameplay often means changing attributes in Studio, not editing Lua.
- **`Util.locationOf(player)`** is used in every server log line — when adding new server logs, follow the format `[ScriptName] <action> @ <Util.locationOf(player)>`.
- **Race protection** on pickup uses a `BeingPickedUp` attribute on the model — preserve this if you touch the pickup path.
- **Base names are hardcoded** as `{"bazapl1", "bazapl2", "bazapl3", "bazapl4"}` in `BrainrotDelivery` and `UpgradeService`. There's a backlog task ("bases-service-абстракция") to centralize this; until then, any new code that iterates bases should use the same list.
- **Built-in Roblox primitives are preferred** over custom systems — ProximityPrompt for interactions, leaderstats for visible counters, attributes for replication. Don't reach for custom keypress scanners or replication frameworks.

## Project tracking

- `.kanbn/` — main task board (kanbn CLI format). `index.md` is the column view; `tasks/*.md` are individual cards. **This is the active board** — do not confuse with anything called `KANBAN.md`.
- `Tasks/` — long-form spec docs for major features (e.g. `Delivery to Base.md`, `Maze Traps.md`). Referenced from kanbn cards.
- `Game Design/` — design docs in markdown. `Main Game Design.md` is the entry point and links to `Brainrots.md`, `Economy.md`, `Labyrinths.md`, `Shop.md`, `Spawn Platforms.md`. Numbers in `UpgradeConfig.lua` come from `Economy.md`.

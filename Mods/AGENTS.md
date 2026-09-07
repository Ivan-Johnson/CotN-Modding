# Mods

The Synchrony mods themselves: `HelloWorldMod`, and `HelloWorldModTests`, an
automated test mod for it. See the repo-root `AGENTS.md` for shared commands
and conventions.

## API reference

* The docs built from the sibling `DocDownloader/` cover the whole Synchrony
  API. Pick whichever entry point fits the situation:
  * `man-crypt 3 necro.game.object.Map` (defined in the dev shell's
    `shellHook`) builds the docs on demand and points MANPATH at the result;
    use this for a single known module.
  * `grep -ri <term> -r result/docs/markdown/` (or the `docs` package's
    output path from `nix build .#docs`) for free-text search across every
    module and component page at once, e.g. when you don't know the exact
    module name.
* Look modules and events up there rather than guessing at signatures; the API
  is large and undocumented outside these pages. Where the docs are silent
  on a detail (return shapes, field names, actual runtime behavior), prefer
  a debug `print()` in a live game session over guessing — a guess that's
  wrong costs a full install/reload/log-tail cycle to discover.

## Dev loop

* Assume by default that CotN is already running with an unpacked mod
  loaded; don't ask the user to confirm this or to run `build-install`
  themselves before trying it. `build-install` (see repo-root `AGENTS.md`)
  is enough to see a change take effect: the ModLoader unmounts and remounts
  the mod on its own, no game restart needed.
* Verify a change actually reloaded by tailing
  `NecroDancer64/NecroDancer.log` for a `Mounting unpacked mod <name>` line
  followed by your new output, e.g. a `print()` shows up as a
  `[Debug] [info]` line.
* The game runs outside this sandbox, so `pgrep`/`ps` won't see its process
  even while it's running and hot-reloading normally. Judge liveness by log
  growth (e.g. `wc -l` on `NecroDancer.log` before/after a change) and fresh
  `Mounting`/output lines, never by process listing.

## Architecture

* The flake is the entire build system. A `runCommand` zips `HelloWorldMod/` so
  the mod directory is the archive root, exposes it as a package, and a
  matching app copies the zip into the game's mod directory. A second mod means
  a second zip derivation and a second install app.
* A mod is a `mod.json` manifest plus Lua entrypoints. `api.scriptPath` names
  the directory Lua loads from; `""` (HelloWorldMod's value) means the archive
  root, while other mods point it at e.g. `scripts/`. `synchronyVersion` pins
  the API version the mod targets.
* Load-time Lua registers handlers — `event.<name>.add(id, phase, fn)`, as in
  `HelloWorld.lua` — and run-time code handles gameplay. Load order and event
  sequence numbers resolve priority when mods touch the same event.
* Published mods commonly use `ModEvent.addUnloadHandler()` to undo settings
  overrides and other state when a mod is disabled, and lean on shared
  settings / snapshot variables / event overrides for their gameplay logic.
  Packaged mods (a `.zip` with `mod.json` at the archive root or under
  `scriptPath`, e.g. `scripts/`) may also bundle non-Lua assets (icons,
  banners, sprites, audio, nested folders like `gfx/`) and occasionally
  editor leftovers such as `.bak` files.

## Known gotchas

* Calling anything that fires an event (e.g. `GameSession.start`,
  `ExtraMode.setActive`, `NetRNG.setSeed`) directly at a script's top level,
  instead of from inside an event handler, throws "Cyclic dependency
  involving ... 'system.mod.ModLoader'" and aborts the whole script load.
  Defer such calls to inside a handler instead.
* For deferred calls, use `Tick.delay(func)` like so:
  ```lua
  -- luacheck: globals myDelayedCall
  myDelayedCall = Tick.delay(function() ... end)
  myDelayedCall()
  ```
* `Marker.Type.STAIRS` markers aren't unique to a level's exit: "All
  Characters Mode" reuses them for its post-run character-select room (one
  staircase per remaining character), and the game lobby reuses them for its
  mode-select room. Logic that keys off stairs markers must account for this
  or disable Extra Modes first (`ExtraMode.setActive`).
* When two handlers share an order key and neither specifies `sequence`, the
  tie does not necessarily break in dependency-load order: empirically, a
  dependent mod's handler ran before the mod it depends on's handler at the
  same order/sequence, the opposite of a literal reading of the "mods sorted
  by load order" doc wording. Don't assume; confirm actual firing order with
  temporary debug `print()`s before relying on it.

## Automated testing

* Each mod that needs behavioral tests gets a sibling `<Mod>Tests` mod (e.g.
  `HelloWorldModTests` for `HelloWorldMod`) rather than test code bundled into
  the mod it tests. This keeps test-only code out of what players install and
  lets the tests mod declare a `dependencies` entry on the mod it exercises in
  `mod.json`, so the ModLoader loads them together in the right order.
* A tests mod drives itself: on load it starts a fixed-seed `GameSession.start`
  run and, via `event.<name>.add` handlers, feeds scripted input
  (`necro.client.Input.add`) and asserts on game state. Results are logged as
  `PASS`/`FAIL`/`SKIP` lines via `print()`, the same channel the dev loop
  already tails in `NecroDancer.log`.
* If an assertion needs a handler to run before or after the mod-under-test's
  handler within the same event/order key, set `sequence` on the *test's*
  handler, not the mod's. Timing needs that exist only to make an assertion
  observable belong in the test, not in the production mod.

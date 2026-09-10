# Mods

The Synchrony mods themselves: `HelloWorldMod`, and `HelloWorldModTests`, a
generic, reusable test-running framework any mod can optionally contribute
test cases to. See the repo-root `AGENTS.md` for shared commands and
conventions.

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
  loaded; don't ask the user to confirm this or to run
  `nix run .#itj-impure-tests` themselves before trying it. It (see
  repo-root `AGENTS.md`) is the whole inner dev loop: it rsyncs both mods,
  forces a fresh test run, waits for it to finish, and prints only the new
  log output — no manual reload or log-tailing needed.
* The game runs outside this sandbox, so `pgrep`/`ps` won't see its process
  even while it's running and hot-reloading normally. If you need to check
  liveness by hand (rather than via `nix run .#itj-impure-tests`), judge it
  by log growth (e.g. `wc -l` on `NecroDancer.log` before/after a change)
  and fresh `Mounting`/output lines, never by process listing.

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
  Define the wrapper once and reuse the same global for every deferred call
  (e.g. one per test in a suite): the sandbox rejects dynamically creating new
  globals (`_G[name] = ...` throws "Attempt to write to non-existent global
  variable"), and re-`Tick.delay`-ing a fresh wrapper under the same global
  name each time breaks its "must be bound to a global variable" binding
  check instead.
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
* The ModLoader detects a reload by a mod's file *content*, not mtime: a bare
  `touch` on an unchanged file does not trigger a remount.
  `nix run .#itj-impure-tests` relies on this — it always changes
  `HelloWorldModTests/api.lua`'s content (a trailing timestamp comment) so
  its test run always re-fires. Since `api.lua` (not the entry script) is
  what mods under test `require` at load-time to register their tests,
  touching it - rather than the entry script - also cascades a reload of
  every mod that successfully required it (e.g. `HelloWorldMod`),
  re-running their `registerTest()` calls: reloading a module always
  triggers a reload of every other script with a load-time dependency on
  it.
* A mod under test's `require()` of `HelloWorldModTests.api` can fail on the
  very first time the two mods ever load together, if `HelloWorldModTests`
  hasn't loaded yet at that point - this only self-heals once
  `HelloWorldModTests` (specifically `api.lua`) reloads again afterwards, per
  the above. In practice, `nix run .#itj-impure-tests` always forces that
  reload, so this only matters for a mod under test's very first-ever
  install alongside the test mod.

## Automated testing

* `HelloWorldModTests` is a single, generic test-running framework, not
  specific to any one mod. It never `require`s (or otherwise depends on) any
  particular mod under test - the dependency direction runs the other way:
  a mod under test optionally `require`s `HelloWorldModTests.api` and calls
  `registerTest()` on it. This keeps the framework reusable across mods, and
  crucially means a mod under test never needs a `dependencies` entry on
  this test-only mod in its `mod.json`, so players installing it don't need
  the test mod installed too.
* A mod under test contributes cases from its own `tests.lua` (e.g.
  `HelloWorldMod/tests.lua`), guarding the cross-mod `require()` in a
  `pcall()`: if `HelloWorldModTests` isn't installed, or hasn't loaded yet
  this cycle, `tests.lua` quietly registers nothing rather than erroring.
* `HelloWorldModTests`'s own entry script (`HelloWorldTests.lua`) registers
  the framework's self-tests (which exercise `api.lua`'s expectFail/crash
  recovery machinery itself, not any mod under test), then starts the suite
  via a `Tick.delay`-deferred call. Deferring by one tick gives every other
  mod under test's own load-time `registerTest()` call - triggered by the
  same reload batch - a chance to run first, since a reload always finishes
  an entire batch of scripts before the next tick, but does not guarantee
  the entry script runs last within that batch.
* The framework drives itself: on load it starts a fixed-seed
  `GameSession.start` run and, via `event.<name>.add` handlers, feeds
  scripted input (`necro.client.Input.add`) and asserts on game state.
  Results are logged as `PASS`/`FAIL`/`SKIP` lines via `print()`, the same
  channel the dev loop already tails in `NecroDancer.log`.
* If an assertion needs a handler to run before or after the mod-under-test's
  handler within the same event/order key, set `sequence` on the *test's*
  handler, not the mod's. Timing needs that exist only to make an assertion
  observable belong in the test, not in the production mod.

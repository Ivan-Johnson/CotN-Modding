# Mods

The Synchrony mods themselves: `HelloWorld`, `ScrapeGameData`,
`AgentBridge`, and
`HelloWorldTests`, a generic, reusable test-running framework any mod can
optionally contribute test cases to. See the repo-root `AGENTS.md` for shared
commands and conventions.

## API reference

* The docs built by `AuthoredDocs/` cover the whole Synchrony
  API. Read them as Markdown under `result/docs/official/markdown/` (run
  `nix build .#docs` if `result` is missing), using the `grep` and `view`
  tools: `grep` for a module or term, `view` for the page. `man-crypt` is a
  dev-shell function for humans; it is not on an agent's `PATH`.
* Look modules and events up there rather than guessing at signatures; the API
  is large and undocumented outside these pages. Where the docs are silent
  on a detail (return shapes, field names, actual runtime behavior), prefer
  a debug `print()` in a live game session over guessing — a guess that's
  wrong costs a full install/reload/log-tail cycle to discover.
* These mirrored docs cover only the in-game Lua API, not `mod.json`'s
  manifest/dependency schema (e.g. what `"dependencies": {"X": true}` means).
  For that, there's no authoritative doc source; rely on empirical testing
  (live reload experiments) or real-world example mods.

## Dev loop

* Before running `nix run .#itj-impure-tests`, lint the Lua:
  `luacheck --config Mods/.luacheckrc Mods`. It catches syntax errors and
  undefined globals in seconds; the live game only reports them after a full
  install/reload cycle. `luajit` is also on `PATH` for running small Lua
  snippets.
* Assume by default that CotN is already running with an unpacked mod
  loaded; don't ask the user to confirm this or to run
  `nix run .#itj-impure-tests` themselves before trying it. It (see
  repo-root `AGENTS.md`) is the whole inner dev loop: it installs the mods,
  forces a fresh test run, waits for it to finish, and prints only the new
  log output — no manual reload or log-tailing needed.
* The game runs outside this sandbox, so `pgrep`/`ps` won't see its process
  even while it's running and live-reloading normally. If you need to check
  liveness by hand (rather than via `nix run .#itj-impure-tests`), judge it
  by log growth (e.g. `wc -l` on `NecroDancer.log` before/after a change)
  and fresh `Mounting`/output lines, never by process listing.

## Architecture

* Each mod lives in `Mods/<name>/`, where `<name>` equals its `mod.json`
  `namespace` and `name` (enforced by the `mods-layout` check). The flake's
  `runCommand`s zip a mod so the mod directory is the archive root, for
  sharing it.
* Development installs go through one bundle mod, not one install per mod; see
  "Installing" below.
* A mod is a `mod.json` manifest plus Lua entrypoints. `api.scriptPath` names
  the directory Lua loads from; `""` (HelloWorld's value) means the archive
  root, while other mods point it at e.g. `scripts/`. `synchronyVersion` pins
  the API version the mod targets.
* Load-time Lua registers handlers — `event.<name>.add(id, phase, fn)`, as in
  `HelloWorld.lua` — and run-time code handles gameplay. Load order and event
  sequence numbers resolve priority when mods touch the same event.
* `HelloWorldTests` drives itself: on load it starts a fixed-seed
  `GameSession.start` run and feeds scripted input
  (`necro.client.Input.add`) from `event.<name>.add` handlers, then asserts on
  game state. Its entry script (`HelloWorldTests.lua`) registers the
  framework's own self-tests, which exercise the expectFail and crash-recovery
  machinery of `api.lua`, then starts the suite from a `Tick.delay`-deferred
  call. Deferring by one tick gives every mod under test its load-time
  `registerTest()` call first, since a reload finishes a whole batch of
  scripts before the next tick; it does not guarantee the entry script runs
  last within that batch.
* `nix run .#itj-impure-tests` always changes `HelloWorldTests/api.lua`'s
  content (a trailing timestamp comment) so the loader remounts it and the run
  re-fires. Mods under test `require` `api.lua`, so the remount also reloads
  them and re-runs their `registerTest()` calls. A mod's first-ever install
  beside the test mod can fail that `require` if `HelloWorldTests` has not
  loaded yet; the forced reload heals it.

## Installing

* The game only loads mods it has enabled; a mod dropped into its mods
  directory is not picked up. So `install-mods` (`nix run .#install-mods --
  Foo Bar`, or just `install-mods Foo Bar` in the dev shell) installs the named
  mods as subfolders of one generated bundle mod (`DevBundle` by default, or
  `ITJ_BUNDLE_NAME`). The bundle is enabled once by hand in the game's Mods
  menu; after that, installing a different set installs and uninstalls mods.
* A module's name is `<mod name>.<path>`, so in the bundle it gains the bundle
  name as a prefix. `install-mods` rewrites `require "<Mod>.…"` to
  `require "<Bundle>.<Mod>.…"` for the installed mods. Any string naming a
  mod's modules other than as a require's whole static argument (e.g. a
  `string.format` pattern, or `require("<Mod>." .. x)`) fails the `mods-layout`
  check. Write such requires as `require "<Mod>.<path>"` or
  `pcall(require, "<Mod>.<path>")`. All of this lives in `bundle-layout.lua`;
  its fixture test is `test-bundle-layout.lua`.
* `install-mods` refuses to install a mod whose `mod.json` dependencies include
  a mod from `Mods/` that isn't also being installed.
* Never delete a mod's installed directory while the game runs: the game's
  live-reload stopped noticing changes after that. Replace the contents
  instead (`rsync --delete`, as `install-mods` does), or restart the game.

## Driving the live game

* `agent-bridge` (a flake app, also in the dev shell) lets an agent observe
  and drive the running game to learn mechanics by experiment, e.g.
  `agent-bridge new-run Dove`, `agent-bridge spawn Skeleton`, `agent-bridge
  entities type=Skeleton show=health`; run it with no arguments for the
  command index and `agent-bridge help COMMAND` for one command's full
  description. `entities` hides held items and wall torches unless given
  `type`, `component` or `id`, or `all=true`; `near=R` and `exclude=T1,T2`
  narrow it further. Any command installs `AgentBridge` first when it is missing.
  Replies are compact text (`--json` for the raw JSON; the mod reports
  entities within 12 tiles, the text shows those within 6) and take about a
  second. `input` takes several actions and replies once
  all have resolved, with each one's outcome, so batch them: `agent-bridge
  input right right up`. The game's events print to stderr as `event:`
  lines after the next command's reply; run `state` to flush the latest.
  The `agent-bridge` in your shell is a built copy of `Mods/agent-bridge.bash`,
  but the mod is installed from source, so after editing the script the CLI
  is stale (no new commands) until the dev shell is re-entered; it warns when
  it detects this. Until then, run `nix run .#agent-bridge -- <cmd>`: the flake
  wrapper supplies `wait_for_log`, so a bare `bash Mods/agent-bridge.bash`
  fails with `wait_for_log: command not found` (after installing the mod).
  `new-run` uses no-beat mode, so time passes only when you act; `new-run
  rhythm=regular` keeps the real-time beat and lets the song end. Installing
  `AgentBridge` replaces the bundle's other mods, and
  `nix run .#itj-impure-tests` (which the pre-commit hook also runs) replaces
  `AgentBridge` with the test mods; the next command reinstalls it, taking a few
  seconds. Bridge commands that change
  the game run from the tick, never via a queued input: an `IDLE` input costs
  the groove chain. See
  `Docs/Adr/0006-agent-bridge-uses-command-file-and-log.md`.
* `agent-bridge route [stairs|X Y] [dig=true]` prints the actions to the
  stairs or a tile, so `agent-bridge input $(agent-bridge route stairs)`
  walks there; use it rather than searching the map by hand. It lists enemies
  on the way on stderr and stops at 50 actions (run it again). Put a step
  onto stairs or a trapdoor last in a batch: after a trapdoor, later actions did not move.
* An `input` that steps onto the stairs or a trapdoor replies before the new
  level loads (up to about 2.5 s later, measured), so a `state` right after
  it can still show the old level. Wait about 3 s (or repeat `state` until
  `lvl` changes) before reading the new level.
* `map` draws each entity type with the same glyph on every call and level,
  and prints its top-left tile, so rows and columns convert to tile
  coordinates without the player's position.
* For fights, take a `snapshot` first and use `scenario ... repeat=N` to
  compare runs, rather than single-stepping; an `=` outcome with
  `damage_dealt` means the attack landed.

### Experiment pitfalls

* The mod waits 30 ticks after each input resolves before queuing the next.
  Without the wait, enemies skipped a move about every 24 beats (a `Slime3`,
  which moves every beat, did so in 40 batched 8-beat runs and never in 49
  beats sent one `idle` per command); 10 ticks still skipped and 25 did not.
  The cause is unknown; the wait is a measured workaround.
* Take a `snapshot` once, before a test loop: each one overwrites the baseline
  that `restore` returns to.
* Read the whole output of a loop. A `grep` that drops the likely killer (the
  boss, say) hides the entity that ends the run.
* After a multi-step `input`, read `at=`: a blocked move does not fail the
  batch, it silently shortens the path.
* Level layouts are random, so use `scenario ... arena=N` for a clean room.
  `spawn ... force` into a wall succeeds and the enemy just sits there, so
  check the tile first. A spawned enemy's first action can come one beat late.
* Deterministic enemies (`Slime2`, `Slime3`, `Skeleton`) act on the same beats
  whether `idle`s are batched or sent singly. Random movers (`Zombie`, `Bat`)
  vary, so compare them with `scenario repeat=N`, never one trace against
  another.
* An enemy that never moves while `aggro.active` is true is probably blocked,
  not asleep: check the tiles and entities around it.
* The diagonal inputs (`up_left` and the like) did nothing as Cadence on one
  1-1 level: `input down_right` came back `TIMED-OUT` with no move and no
  turn. Tried once.
* After a win or death the run-summary screen swallows every action: `input`
  replies `TIMED-OUT` after about 5000 ticks and `turn` never moves, though
  `restore` still works. `state` prints `RUN SUMMARY SCREEN UP` while
  `RunSummary.getActiveSummary()` is truthy. When an `input` times out and
  `turn` is unchanged, check `state` for that line instead of polling or
  listing processes; if it is absent, ask the user what is on screen.
  Finish boss-fight experiments before taking the exit stairs, which ends the
  run.
* `clear` removes every enemy with an `ai`, shopkeepers included, and a
  dead shopkeeper makes shop wares free. Do not `clear` before a shop test.
* `spawn X Y` takes absolute tile coordinates, not offsets from the player.
* `new-run seed=N` reproduced the same level and entity list on a second run;
  use it so a death does not lose the level. Entity ids differ between runs.
* `idle` is the no-op beat and drops the groove chain, so it is also how a
  beat is "missed" in no-beat mode.
* `route` crosses a `ShrineOfBlood` as if it were floor (no `ai`, `health`,
  `trap` or `item`; collision mask 2), costing 10 health in one action. It
  treats chests the same way (untested). Check the `map` legend and `entities`
  before running a route you cannot afford to lose.

## Read when needed

* `AuthoredDocs/Src/README.md`: an index of hand-written guides. Read it
  first when hitting a Lua error, an event-ordering surprise, a test problem,
  or a mod that will not reload, and follow its links.

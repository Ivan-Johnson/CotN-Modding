# Testing a mod

For mod authors. How a mod contributes test cases to the repo's `HelloWorldTests`
framework, and how the mod loader reloads mods. The framework's dependency
direction is recorded in `Docs/Adr/0003-test-framework-never-depends-on-mods.md`
at the repo root; how the framework works inside is in `Mods/AGENTS.md`.

## Exploring the game with a test

Unit tests are the default way to learn how the game works. For a mechanics
question:

1. Register a test in a mod's `tests.lua` (see below). Its `onLoad` sets up
   the situation and calls `api.observe(key, value)` for each value you want.
2. Lint with `luacheck --config Mods/.luacheckrc Mods`.
3. Run just that test: `nix run .#itj-impure-tests -- <testName>`.
4. Read the `OBSERVED <test> <key>=<value>` lines and the `PASS`/`FAIL` line
   in what it prints. A Lua error in `onLoad` shows as `FAIL` with the message.

The command returns in a few seconds. Each run logs its own `Starting Single
Zone run with seed N` line with a random N; that is the game's choice before
the framework overrides it, and the level is generated from the fixed seed
(`observe` reports it). Once the question is answered, delete the scratch test or keep
it as a regression test with real assertions.

## Writing tests

* A mod under test contributes cases from its own `tests.lua` (for example
  `HelloWorld/tests.lua`), guarding the cross-mod `require()` of
  `HelloWorldTests.api` in a `pcall()`, since the framework may not be loaded.
* Registering a name that is already registered replaces the earlier test: a
  reload can run a mod's load-time `registerTest()` calls again, and the
  replacement keeps each test running once. The entrypoint fails if a test
  still reports twice.
* Results print as `PASS`, `FAIL`, `XFAIL` or `XPASS` lines to
  `NecroDancer.log`, each ending in how long the test took, e.g. `PASS name
  (212 ticks)`. A tick is about a millisecond, but the Synchrony sandbox has no
  `os` library, so there is no wall clock; ticks slow down on a loaded
  machine. The completion line gives the suite's total in ticks, and
  `nix run .#itj-impure-tests` adds the wall-clock seconds.
* To answer a question about the game instead of only asserting, call
  `api.observe(key, value)` from `onLoad`. It prints `[HelloWorldTests]
  OBSERVED <test> <key>=<value>` before the test's `PASS`/`FAIL` line, and
  `nix run .#itj-impure-tests` shows it with the rest of the new log.
* To run one test alone, pass its name: `nix run .#itj-impure-tests --
  <testName>`. It runs from the same fixed seed as in the full suite, and
  fails with `no registered test has this name` for an unknown name. The
  entrypoint hands the name to the framework in a
  `HelloWorldTests/selected-test.txt` file that `install-mods` creates (the
  Lua sandbox has no environment variables); the next plain run removes it.
* To run every test registered by some files, pass `--files`: `nix run
  .#itj-impure-tests -- --files weapon-tests.lua,bomb-tests.lua`. `registerTest`
  tags each test with the basename of the file that called it, so tests made in
  a loop belong to that file. A helper that registers tests for its caller, as
  `fixtures.scene` does, tags them with `api.callerFile()`; a test with no tag
  runs in every file selection. The file's tests run in the full suite's
  order, and each test still starts from a fresh fixed-seed session. The
  commit hook runs this way for a commit that changes only test files.
* To play the game step by step, mark the test `noBeat = true` (time passes
  only when the player acts) and `async = true`. Its `onLoad(seed, finish)`
  then drives the run with `api.play({"up", "idle", ...}, afterEach, finish)`,
  which sends one action at a time and calls `afterEach(index, name,
  resolved)` once the game has settled. `finish()` passes the test and
  `finish(message)` fails it; an error in any callback fails it too. A test
  that has not finished within 18000 ticks of starting, level load included,
  fails with `timed out after N ticks` and the next test runs; set
  `timeoutTicks` on the test to change its limit. Use
  `api.afterTicks(n, fn)` to wait. An action that does not advance the turn,
  such as a bump into a wall, reports `resolved` false after 1500 ticks.
  `HelloWorldTests.fixtures` has the shared helpers: `openArena(radius)`
  clears the level's enemies and opens an arena of floor, `spawn`, `player`,
  `health`, `wallColumn(x, firstY, lastY, tileType)`, `tileName(x, y)`,
  `repeated(value, count)`, `assertAt(entity, x, y, what)`, and
  `scene{name, radius, prepare, setup, actions, checks}`, which registers a
  no-beat test that opens the arena, runs `prepare` then `setup`, plays
  `actions`, and calls `checks[index](state, resolved)` after each. Check
  `fixtures.lua` before writing your own scene, wallColumn, health or
  assertAt helper. `Mods/HelloWorld/ghost-tests.lua` is a worked example.
* If an assertion needs a handler to run before or after the mod-under-test's
  handler within the same event and order key, set `sequence` on the test's
  handler, not the mod's. Timing that exists only to make an assertion
  observable belongs in the test, not in the production mod.

## Reloading

* The mod loader reloads a mod when a file's content changes, not its mtime.
  A bare `touch` on an unchanged file is believed not to trigger a remount
  (`guess`; untested, see #42).
* Reloading a module reloads every other script with a load-time dependency on
  it, for example every mod that `require`s the changed module.

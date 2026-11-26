# Testing a mod

For mod authors. How a mod contributes test cases to the repo's `HelloWorldTests`
framework, and how the mod loader reloads mods. The framework's dependency
direction is recorded in `Docs/Adr/0003-test-framework-never-depends-on-mods.md`
at the repo root. The test table's fields, `api.play` and `api.observe` are
documented in `Mods/HelloWorldTests/api.lua`; the shared helpers, `scene`
among them, in `Mods/HelloWorldTests/fixtures.lua`.

## Exploring the game with a test

Unit tests are the default way to learn how the game works. For a mechanics
question:

1. Register a test in a mod's `tests.lua` (see below). Its `onLoad` sets up
   the situation and calls `api.observe(key, value)` for each value you want.
2. Lint with `luacheck --config Mods/.luacheckrc Mods`. It catches syntax
   errors and undefined globals in seconds; the live game only reports them
   after a full install and reload.
3. Run just that test: `nix run .#itj-impure-tests -- <testName>`. It runs
   from the same fixed seed as in the full suite. To run every test
   registered by some files instead: `nix run .#itj-impure-tests -- --files
   weapon-tests.lua,bomb-tests.lua`.
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
* A helper that registers tests for its caller, as `fixtures.scene` does,
  tags them with `api.callerFile()` so `--files` selects them with the
  caller's file; a test with no tag runs in every file selection.
* To play the game step by step, mark the test `noBeat = true` and
  `async = true` and drive it with `api.play`. Check `fixtures.lua` before
  writing your own scene, wallColumn, health or assertAt helper.
  `Mods/HelloWorld/ghost-tests.lua` is a worked example.
* If an assertion needs a handler to run before or after the mod-under-test's
  handler within the same event and order key, set `sequence` on the test's
  handler, not the mod's. Timing that exists only to make an assertion
  observable belongs in the test, not in the production mod.

## Reloading

* The mod loader reloads a mod when a file's content changes, not its mtime.
* Reloading a module reloads every other script with a load-time dependency on
  it, for example every mod that `require`s the changed module.
* A mod's first-ever install beside `HelloWorldTests` can fail its `require`
  of `HelloWorldTests.api` if the framework has not loaded yet; the forced
  reload of `nix run .#itj-impure-tests` heals it.
* Never delete a mod's installed directory while the game runs: the game's
  live-reload stopped noticing changes after that. Replace the contents
  instead (`rsync --delete`, as `install-mods` does), or restart the game.

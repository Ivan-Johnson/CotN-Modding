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

Measured with a one-line test that observed the stairs count: the command
returned in a few seconds, printed the `OBSERVED` and `PASS` lines, and
exited with `All tests pass`. The test's lines appeared twice in the output
(two runs, each with its own `Starting ... run with seed` line); cause not
investigated. Once the question is answered, delete the scratch test or keep
it as a regression test with real assertions.

## Writing tests

* A mod under test contributes cases from its own `tests.lua` (for example
  `HelloWorld/tests.lua`), guarding the cross-mod `require()` of
  `HelloWorldTests.api` in a `pcall()`, since the framework may not be loaded.
* Results print as `PASS`, `FAIL` or `SKIP` lines to `NecroDancer.log`.
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

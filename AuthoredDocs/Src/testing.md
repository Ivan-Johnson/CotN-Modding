# Testing a mod

For mod authors. How a mod contributes test cases to the repo's `HelloWorldTests`
framework, and how the mod loader reloads mods. The framework's dependency
direction is recorded in `Docs/Adr/0003-test-framework-never-depends-on-mods.md`
at the repo root; how the framework works inside is in `Mods/AGENTS.md`.

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

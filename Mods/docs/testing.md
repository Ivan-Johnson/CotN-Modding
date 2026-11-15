# Automated testing

The framework's dependency direction is recorded in
`docs/adr/0003-test-framework-never-depends-on-mods.md` at the repo root.

## Writing tests

* A mod under test contributes cases from its own `tests.lua` (e.g.
  `HelloWorldMod/tests.lua`), guarding the cross-mod `require()` of
  `HelloWorldModTests.api` in a `pcall()`.
* The framework drives itself: on load it starts a fixed-seed
  `GameSession.start` run and, via `event.<name>.add` handlers, feeds
  scripted input (`necro.client.Input.add`) and asserts on game state.
  Results are logged as `PASS`/`FAIL`/`SKIP` lines via `print()`, the same
  channel the dev loop already tails in `NecroDancer.log`.
* If an assertion needs a handler to run before or after the mod-under-test's
  handler within the same event/order key, set `sequence` on the *test's*
  handler, not the mod's. Timing needs that exist only to make an assertion
  observable belong in the test, not in the production mod.

## Framework internals

* `HelloWorldModTests`'s own entry script (`HelloWorldTests.lua`) registers
  the framework's self-tests (which exercise `api.lua`'s expectFail/crash
  recovery machinery itself, not any mod under test), then starts the suite
  via a `Tick.delay`-deferred call. Deferring by one tick gives every other
  mod under test's own load-time `registerTest()` call - triggered by the
  same reload batch - a chance to run first, since a reload always finishes
  an entire batch of scripts before the next tick, but does not guarantee
  the entry script runs last within that batch.

## Reloading

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

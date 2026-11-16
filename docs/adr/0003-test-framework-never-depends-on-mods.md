# The test framework never depends on a mod under test

`HelloWorldTests` is one generic framework. It never `require`s a mod under
test; the dependency runs the other way, with each mod optionally `require`ing
`HelloWorldTests.api` and calling `registerTest()`. This keeps the framework
reusable, and a mod under test needs no `dependencies` entry on the test-only
mod in its `mod.json`, so players need not install it.

## Consequences

* The cross-mod `require()` is guarded by `pcall()`, so a mod's `tests.lua`
  quietly registers nothing when the framework is absent.

# Testing a mod

For mod authors. How a mod contributes test cases to the repo's `TestFramework`
framework, and how the mod loader reloads mods. The framework's dependency
direction is recorded in `Docs/Adr/0003-test-framework-never-depends-on-mods.md`
at the repo root. The test table's fields, `api.play` and `api.observe` are
documented in `Mods/TestFramework/api.lua`; the shared helpers, `scene`
among them, in `Mods/TestFramework/fixtures.lua`.

## Exploring the game with a test

Unit tests are the default way to learn how the game works. For a mechanics
question:

1. Register a test in the claim test file of the page the answer belongs on,
   `Mods/ClaimTests/<page>.lua` (see below). Its `onLoad` sets up
   the situation and calls `api.observe(key, value)` for each value you want.
2. Lint with `luacheck --config Mods/.luacheckrc Mods`. It catches syntax
   errors and undefined globals in seconds; the live game only reports them
   after a full install and reload.
3. Run just that test: `nix run .#itj-impure-tests -- <testName>`. It runs
   from the same fixed seed as in the full suite. It takes one name;
   `-- --help` lists the other forms. To run every test registered by some
   files instead: `nix run .#itj-impure-tests -- --files weapons.lua,bombs.lua`.
4. Read the `OBSERVED <test> <key>=<value>` lines and the `PASS`/`FAIL` line
   in what it prints; the last line totals the results. A Lua error in
   `onLoad` shows as `FAIL` with the message.

The command returns in a few seconds. Each run logs its own `Starting Single
Zone run with seed N` line with a random N; that is the game's choice before
the framework overrides it, and the level is generated from the fixed seed
(`observe` reports it). Once the question is answered, delete the scratch test or keep
it as a regression test with real assertions.

## Writing tests

* A mod under test contributes code tests from its own `tests.lua` or
  `*-tests.lua` (for example `HelloWorld/tests.lua`). Tests are selected by
  file basename, so no two mods may share one. Claim tests, which back a
  page's claims about the game, go in `Mods/ClaimTests/<page>.lua`, which the
  run installs without the mods under test. Either guards the cross-mod
  `require()` of `TestFramework.api` in a `pcall()`, since the framework may
  not be loaded.
* A test must pass every time it plays. Whatever the fixed seed does not fix
  changes from run to run, such as what the game rolls during play: where a
  shopkeeper teleports, or where a skeleton runs once its head is knocked off.
  Pin it in the test, or assert only what holds every time. One pass does not
  show this, so run a new or changed test's file several times in a row before
  committing it.
* Registering a name that is already registered replaces the earlier test: a
  reload can run a mod's load-time `registerTest()` calls again, and the
  replacement keeps each test running once. The entrypoint fails if a test
  still reports twice.
* Load-time code may not read the entity schema (Synchrony's `overview.md`,
  "Load-time vs. run-time"): `Entities.getEntityTypesWithComponents` often
  returns nothing there, so tests registered in a loop over it go missing.
  Register per-type tests from a fixed list, and check the list against the
  schema inside a test, where the schema is always built.
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
  `async = true` and drive it with `api.play`; read "No-beat mode" below
  first. Check `fixtures.lua` before writing your own scene, wallColumn,
  health or assertAt helper.
* A survey test, one that checks odds or what a set of levels holds over
  many runs or trials, calls `api.smallSample()` from `onLoad` and, when it
  returns true, plays only a few runs or trials and skips the assertions
  that need the full sample. A harness change runs every test that way
  (`nix run .#itj-impure-tests -- --small-samples`), so that the change
  still exercises the survey code without waiting minutes for it.
  `fixtures.zoneCensus` and `fixtures.assertAllPresent` do this themselves.
* To check what a zone's levels hold, survey them with `fixtures.zoneCensus`,
  which generates the same set of seeded levels every time. A test that
  wants other seeds than the fixed one sets them with
  `api.setSeedOverride`: the framework's `levelGenerate` handler can run
  after a test file's own, undoing its seed.
  `Mods/ClaimTests/ghost.lua` is a worked example.
* Played to the beat, `api.play` holds each input until the next beat is
  near, since an input sent a fixed number of ticks after the last drifts off
  the beat and, once early enough, counts as a missed beat: the player stays
  put although the turn advances.
* To time inputs within a beat, for a trap's fuse or the stairs' descent,
  play a `fixtures.timeline`: it sends each input at a set offset from a
  beat, built on `api.atBeat`, `api.atMusicTime` and `api.send`, and
  records when each watched value changed, missed beats included. Music
  time moves every tick, so an input lands within about a millisecond of
  its target. The game, though, judges an input against its beatmap, which
  at times falls a beat or two behind the music; the timeline checks the
  beatmap before each input and starts over at a later beat when it is
  behind before the first. Before playing one, wait for the player's
  `rhythmLeniency.remainingTurns` to reach 0, as well as its invincibility.
  `Mods/ClaimTests/sub-beat-timing.lua` is a worked example.
  Name such tests with letters, digits and `_` only: the runner reads a
  test's name up to the first other character, so names that differ only
  after a `+`, `-` or `.` look like one test reported twice.
* If an assertion needs a handler to run before or after the mod-under-test's
  handler within the same event and order key, set `sequence` on the test's
  handler, not the mod's. Timing that exists only to make an assertion
  observable belongs in the test, not in the production mod.

## No-beat mode

No-beat mode runs the game on two clocks, and a test that checks the wrong
one sees an effect that "never happens". Every effect that has seemed
missing in no-beat mode so far turned out to land at a different time.

* **Beats pass only on input.** Whatever counts beats or turns waits for the
  player's next action: enemy moves, a bomb's fuse, the length of a
  confusion, and the invincibility a level starts with. Waiting ticks
  advances none of them. After 3000 ticks a lit bomb is still lit and the
  player still invincible, so a spike trap stepped onto as the first action
  costs nothing. The game sets that invincibility a tick after `onLoad`, so
  clearing it there does nothing; idle until
  `invincibility.remainingTurns` is 0, as `Mods/ClaimTests/traps.lua` does.
* **Delays run in real time.** An effect that lands a moment after the action
  that caused it lands with or without another input, as
  `necro.game.system.Delay` describes its timed delays. A trap's effect
  (spikes, confusion, teleport, scatter, a bomb trap's bomb) lands after its
  fuse ([sub-beat-timing.md](./sub-beat-timing.md#trap-fuses)), 100 to 300
  ticks after the step onto it, as does a travel rune's trip, and a trapdoor's level change
  about 3000 ticks after. That is later than `api.play` settles, so a check
  run as `api.play` returns sees nothing yet. The delay lands in a turn of
  its own, so `Turn.getCurrentTurnID()` advances with no input.
* **The next input lands a pending delay first.** An input sent before a
  delay runs out, as `api.play` sends a list, lands the effect before the
  input acts (`Delay.Flags.processOnPlayerAction`): a confusion trap
  reverses the very next move. It is the fuse rule of sub-beat-timing.md,
  which `api.play`'s quick inputs hit every time. A level change still waits
  out its own delay.

On the beat, `api.play` sends at most one input a beat, which outlasts most
delays, so the same scene there shows each effect between two inputs.

Before concluding that something does not happen in no-beat mode, rule out
both clocks: poll for a few thousand ticks after the action with no input,
then send a few idles and check again. If the effect shows up after either,
it is a timing difference, not a mode difference. A difference that survives
both is a real one only once the same scene, played to the beat, shows the
effect; back it with a test that runs both modes. The tests in
`Mods/ClaimTests/testing.lua` are worked examples.

## Reloading

* The mod loader reloads a mod when a file's content changes, not its mtime.
* Reloading a module reloads every other script with a load-time dependency on
  it, for example every mod that `require`s the changed module.
* One install reloads the game in several batches, and a mod new to the
  bundle can load after the framework. So `nix run .#itj-impure-tests` names
  the test files it expects, and the suite starts only once each has
  registered a test, or fails naming the ones that never did.
* A mod's first-ever install beside `TestFramework` can fail its `require`
  of `TestFramework.api` if the framework has not loaded yet; the forced
  reload of `nix run .#itj-impure-tests` heals it.
* Never delete a mod's installed directory while the game runs: the game's
  live-reload stopped noticing changes after that. Replace the contents
  instead (`rsync --delete`, as `install-mods` does), or restart the game.

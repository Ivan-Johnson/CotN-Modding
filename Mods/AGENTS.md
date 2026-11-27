# Mods

The Synchrony mods themselves: `HelloWorld`, `MarvTheCowardlySheep`,
`ScrapeGameData`, and `TestFramework`, a generic, reusable test-running
framework any mod can optionally contribute test cases to.

## Map

Each file's header comment says what it does; this map says what the names
do not: each group's role and what it is coupled to.

* `HelloWorld/`: a minimal mod with gameplay code, and its code tests in
  `tests.lua`.
* `ClaimTests/`: the claim tests, with no gameplay code. `<page>.lua` backs
  `AuthoredDocs/Src/<page>.md` and nothing else; the `claim-tests-layout`
  check requires the page. The test run never installs it beside a
  code-test mod (ADR 0008).
* `TestFramework/`: the test framework. `api.lua` holds the test contract,
  `fixtures.lua` the shared helpers, and `TestFramework.lua` the framework's
  self-tests and the suite start.
* `MarvTheCowardlySheep/`: the character mod for Muriel and her sheep
  Marv, and its code tests in `marv-tests.lua`. Its game-design terms are in
  its own `GLOSSARY.md`.
* `ScrapeGameData/`: the GameData context's scraper. Its `DATA` log lines are
  a format shared with `GameData/reassemble-scrape.bash`.
* `LiveGame/`: the tooling that installs mods into the game and runs the
  live tests, plus the offline tests. It is not a mod.
  * `live-game-run.bash`: the one way to drive the live game (ADR 0009). It
    locks the game, installs, reloads, checks that the game loaded the
    install, and waits for a log line.
  * `install-mods.bash` and `bundle-layout.lua`: the dev install into one
    bundle mod (ADR 0004), internal to `live-game-run`. `bundle-layout.lua`
    also runs the `mods-layout` check.
  * `itj-impure-tests.bash`: the live test run. It is coupled to
    `TestFramework/api.lua` both ways: it parses the result and completion
    lines `api.lua` prints, and has `live-game-run` write the
    `selected-test.txt` that `api.lua` reads. `itj-impure-scope.bash`
    decides when `build-release` runs it. Its last line totals the run's
    results, and `build-release` shows that line when the run passes, so
    keep it last.
  * `test-<name>.*`: the offline test of `<name>`, run by `nix flake check`,
    except `test-fake-game.bash`, the fake game those tests share.
    `test-bytecode-api.lua` tests `ScrapeGameData/BytecodeApi.lua`; it lives
    here because everything under a mod's directory is installed into the
    game. Changing one runs no live test (ADR 0008).
* `flake-module.nix`: wires everything above into packages, checks, apps and
  the dev shell, and exports `liveGame` (`liveGameRun`) to
  `GameData/flake-module.nix`.

## API reference

* The docs built by `AuthoredDocs/` cover the whole Synchrony
  API. Read them as Markdown under `result/docs/official/markdown/` (run
  `nix build .#docs` if `result` is missing), using the `grep` and `view`
  tools: `grep` for a module or term, `view` for the page. `man-crypt` is a
  dev-shell function for humans; it is not on an agent's `PATH`.
* Look modules and events up there rather than guessing at signatures; the API
  is large and undocumented outside these pages. Where the docs are silent
  on a detail (return shapes, field names, actual runtime behavior), prefer
  a test that observes it (repo-root `AGENTS.md`, "Learning about the game")
  over guessing — a guess that's wrong costs a full install/reload/log-tail cycle
  to discover.
* These mirrored docs cover only the in-game Lua API, not `mod.json`'s
  manifest/dependency schema (e.g. what `"dependencies": {"X": true}` means).
  For that, there's no authoritative doc source; rely on empirical testing
  (live reload experiments) or real-world example mods.

## Dev loop

* `nix run .#itj-impure-tests` is the whole inner dev loop: in one pass it
  installs every code-test mod (each mod with a `tests.lua` or
  `*-tests.lua`) and `TestFramework` with `live-game-run`, and in a
  second pass `ClaimTests` and `TestFramework`. Each pass locks the game,
  forces `TestFramework` to reload so its test run fires (in the dev
  shell, every installed Lua file, as `ITJ_BUNDLE_STAMP_ALL` is set),
  waits for the suite, and prints only the new `NecroDancer.log` lines. The run's last
  line totals both passes, and every round with `--repeat`, e.g.
  `itj-impure-tests: all tests pass: 132 PASS,
  3 XFAIL, 0 FAIL, 0 XPASS`; read that rather than counting lines in
  `NecroDancer.log`. CotN live-reloads
  unpacked mods, so no manual reload or log-tailing is needed. It's an `app`, not a
  `check`, because it needs a running, native Steam/Proton CotN instance.
  Writing, linting and running a test: `AuthoredDocs/Src/testing.md`.
* `build-release`, which the `commit-msg` and `pre-push` hooks run, runs only
  the live tests the changed paths can affect, through `itj-impure-tests
  --files`, or every test with survey tests at their small sample, through
  `itj-impure-tests --small-samples`, when the harness changed.
  `itj-impure-scope.bash` decides; its header has the rules (ADR 0008). A game update changes no path, so after one, run everything:
  `nix run .#itj-impure-tests` with no arguments.
* `luajit` is on `PATH` for running small Lua snippets.
* Assume by default that CotN is already running with an unpacked mod
  loaded; don't ask the user to confirm this or to run
  `nix run .#itj-impure-tests` themselves before trying it.
* The game runs outside this sandbox, so `pgrep`/`ps` won't see its process
  even while it's running and live-reloading normally. If you need to check
  liveness by hand (rather than via `nix run .#itj-impure-tests`), judge it
  by log growth (e.g. `wc -l "$COTN_LOG"`, the game's `NecroDancer.log`,
  before/after a change) and fresh `Mounting`/output lines, never by process
  listing. For the user, the dev shell's `cotn-log-idle-notify [SECONDS]`
  sends a desktop notification when the log has been idle for more than
  `SECONDS` (default 45).

## Architecture

* Each mod lives in `Mods/<name>/`, where `<name>` equals its `mod.json`
  `namespace` and `name`, and all mods declare one `synchronyVersion`, which
  the bundle copies (both enforced by the `mods-layout` check).
* Development installs go through one bundle mod, via `live-game-run` (`nix
  run .#live-game-run -- Foo Bar`, or `live-game-run Foo Bar` in the dev
  shell), which also locks the game for the install; why and how:
  `Docs/Adr/0004-dev-installs-go-through-a-bundle-mod.md` and
  `Docs/Adr/0009-one-module-owns-the-live-game-instance.md`. The bundle
  is enabled once by hand in the game's Mods menu.
* Write a require of a mod's own modules as `require "<Mod>.<path>"` or
  `pcall(require, "<Mod>.<path>")`, so the install-time rewrite finds it; any
  other string naming a mod's modules fails the `mods-layout` check. The
  rules live in `LiveGame/bundle-layout.lua`; its fixture test is
  `test-bundle-layout.lua`.

## Read when needed

* `AuthoredDocs/Src/README.md`: an index of hand-written guides. Read it
  first when hitting a Lua error, an event-ordering surprise, a test problem,
  or a mod that will not reload, and follow its links.

## Glossary

@GLOSSARY.md

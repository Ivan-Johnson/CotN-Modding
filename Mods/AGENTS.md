# Mods

The Synchrony mods themselves: `HelloWorld`, `ScrapeGameData`, and
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
  a test that observes it (repo-root `AGENTS.md`, "Learning about the game")
  over guessing — a guess that's wrong costs a full install/reload/log-tail cycle
  to discover.
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

## Read when needed

* `AuthoredDocs/Src/README.md`: an index of hand-written guides. Read it
  first when hitting a Lua error, an event-ordering surprise, a test problem,
  or a mod that will not reload, and follow its links.

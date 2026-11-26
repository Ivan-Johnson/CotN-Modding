# Mods

The Synchrony mods themselves: `HelloWorld`, `ScrapeGameData`, and
`HelloWorldTests`, a generic, reusable test-running framework any mod can
optionally contribute test cases to.

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

* `nix run .#itj-impure-tests` is the whole inner dev loop: it installs
  `HelloWorld` and `HelloWorldTests` with `install-mods`, forces
  `HelloWorldTests` to reload so its test run fires, waits for the suite, and
  prints only the new `NecroDancer.log` lines. CotN live-reloads unpacked
  mods, so no manual reload or log-tailing is needed. It's an `app`, not a
  `check`, because it needs a running, native Steam/Proton CotN instance.
  Writing, linting and running a test: `AuthoredDocs/Src/testing.md`.
* `luajit` is on `PATH` for running small Lua snippets.
* Assume by default that CotN is already running with an unpacked mod
  loaded; don't ask the user to confirm this or to run
  `nix run .#itj-impure-tests` themselves before trying it.
* The game runs outside this sandbox, so `pgrep`/`ps` won't see its process
  even while it's running and live-reloading normally. If you need to check
  liveness by hand (rather than via `nix run .#itj-impure-tests`), judge it
  by log growth (e.g. `wc -l` on `NecroDancer.log` before/after a change)
  and fresh `Mounting`/output lines, never by process listing.

## Architecture

* Each mod lives in `Mods/<name>/`, where `<name>` equals its `mod.json`
  `namespace` and `name` (enforced by the `mods-layout` check).
* Development installs go through one bundle mod, `install-mods` (`nix run
  .#install-mods -- Foo Bar`, or `install-mods Foo Bar` in the dev shell); why
  and how: `Docs/Adr/0004-dev-installs-go-through-a-bundle-mod.md`. The bundle
  is enabled once by hand in the game's Mods menu.
* Write a require of a mod's own modules as `require "<Mod>.<path>"` or
  `pcall(require, "<Mod>.<path>")`, so the install-time rewrite finds it; any
  other string naming a mod's modules fails the `mods-layout` check. The
  rules live in `bundle-layout.lua`; its fixture test is
  `test-bundle-layout.lua`.

## Read when needed

* `AuthoredDocs/Src/README.md`: an index of hand-written guides. Read it
  first when hitting a Lua error, an event-ordering surprise, a test problem,
  or a mod that will not reload, and follow its links.

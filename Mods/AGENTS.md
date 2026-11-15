# Mods

The Synchrony mods themselves: `HelloWorldMod`, and `HelloWorldModTests`, a
generic, reusable test-running framework any mod can optionally contribute
test cases to. See the repo-root `AGENTS.md` for shared commands and
conventions.

## API reference

* The docs built from the sibling `DocDownloader/` cover the whole Synchrony
  API. Read them as Markdown under `result/docs/markdown/` (run
  `nix build .#docs` if `result` is missing), using the `grep` and `view`
  tools: `grep` for a module or term, `view` for the page. `man-crypt` is a
  dev-shell function for humans; it is not on an agent's `PATH`.
* Look modules and events up there rather than guessing at signatures; the API
  is large and undocumented outside these pages. Where the docs are silent
  on a detail (return shapes, field names, actual runtime behavior), prefer
  a debug `print()` in a live game session over guessing — a guess that's
  wrong costs a full install/reload/log-tail cycle to discover.
* These mirrored docs cover only the in-game Lua API, not `mod.json`'s
  manifest/dependency schema (e.g. what `"dependencies": {"X": true}` means).
  For that, there's no authoritative doc source; rely on empirical testing
  (live reload experiments) or real-world example mods.

## Dev loop

* Assume by default that CotN is already running with an unpacked mod
  loaded; don't ask the user to confirm this or to run
  `nix run .#itj-impure-tests` themselves before trying it. It (see
  repo-root `AGENTS.md`) is the whole inner dev loop: it rsyncs both mods,
  forces a fresh test run, waits for it to finish, and prints only the new
  log output — no manual reload or log-tailing needed.
* The game runs outside this sandbox, so `pgrep`/`ps` won't see its process
  even while it's running and live-reloading normally. If you need to check
  liveness by hand (rather than via `nix run .#itj-impure-tests`), judge it
  by log growth (e.g. `wc -l` on `NecroDancer.log` before/after a change)
  and fresh `Mounting`/output lines, never by process listing.

## Architecture

* The flake is the entire build system. A `runCommand` zips `HelloWorldMod/` so
  the mod directory is the archive root, exposes it as a package, and a
  matching app copies the zip into the game's mod directory. A second mod means
  a second zip derivation and a second install app.
* A mod is a `mod.json` manifest plus Lua entrypoints. `api.scriptPath` names
  the directory Lua loads from; `""` (HelloWorldMod's value) means the archive
  root, while other mods point it at e.g. `scripts/`. `synchronyVersion` pins
  the API version the mod targets.
* Load-time Lua registers handlers — `event.<name>.add(id, phase, fn)`, as in
  `HelloWorld.lua` — and run-time code handles gameplay. Load order and event
  sequence numbers resolve priority when mods touch the same event.

## Read when needed

* `docs/gotchas.md`: Lua errors at load time, event ordering, `Tick.delay`,
  stairs markers, and reverse-engineering an entity's behavior with
  `print(ev)`.
* `docs/testing.md`: writing or debugging tests, or a mod not reloading.

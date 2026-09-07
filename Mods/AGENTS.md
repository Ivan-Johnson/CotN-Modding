# Mods

The Synchrony mods themselves, currently one minimal mod, `HelloWorldMod`. See
the repo-root `AGENTS.md` for shared commands and conventions.

## API reference

* The docs built from the sibling `DocDownloader/` put the whole Synchrony API
  on the dev shell's MANPATH as flat section 3 pages named after the module:
  `man 3 necro.game.object.Map`, `apropos -s 3 <term>`. The same content is
  under the package's `markdown/`.
* Look modules and events up there rather than guessing at signatures; the API
  is large and undocumented outside these pages.

## Dev loop

* With CotN running and an unpacked mod already loaded, `build-install` (see
  repo-root `AGENTS.md`) is enough to see a change take effect: the ModLoader
  unmounts and remounts the mod on its own, no game restart needed.
* Verify a change actually reloaded by tailing
  `NecroDancer64/NecroDancer.log` for a `Mounting unpacked mod <name>` line
  followed by your new output, e.g. a `print()` shows up as a
  `[Debug] [info]` line.

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
* `CotN-modding-notes.md` is the distilled research on the modding model and on
  patterns observed in published mods, e.g. `ModEvent.addUnloadHandler()` to
  undo settings overrides when a mod is disabled. Extend it rather than
  re-deriving findings.

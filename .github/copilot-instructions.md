# Copilot instructions

Crypt of the NecroDancer is a rhythm-based roguelike where movement, combat, and
survival happen to the beat. Its Synchrony version adds full Lua modding
support. This repo is for building Synchrony mods; it currently holds one
minimal mod, `HelloWorldMod`.

## Commands

* `nix build` packages `HelloWorldMod/` into `result/HelloWorldMod.zip`.
* `nix run .#install-hello-world-mod` copies that zip into
  `~/.local/share/NecroDancer/downloadedMods/`. The `build-install` shell alias
  does both, but aliases only exist in an interactive shell.
* `nix flake check` evaluates every flake output.
* `my-nix-format-all` formats all `.nix` files; `my-nix-format --check FILE`
  verifies a single one.
* `build-release` is the shared pre-push check, but it no-ops unless
  `ITJ_GIT_PREPUSH_ENABLE_NIX_CHECKS` is set in the environment — it prints
  "Pre-push has nothing to do" and exits 0. Verify with `nix flake check` plus
  `my-nix-format-all` instead of trusting it.

There is no test suite. Mods are validated by installing them and toggling them
in the game's **Customize -> Mods** menu; unpackaged Lua mods live-reload on
Linux via file watching.

## API reference

* The `itj_cotn_docs` flake input (built by the sibling `CotN-doc-downloader`
  repo) puts the whole Synchrony API on the dev shell's MANPATH as flat section
  3 pages named after the module: `man 3 necro.game.object.Map`,
  `apropos -s 3 <term>`. The same content is under the package's `markdown/`.
* Look modules and events up there rather than guessing at signatures; the API
  is large and undocumented outside these pages.

## Architecture

* `flake.nix` is the entire build system. A `runCommand` zips `HelloWorldMod/`
  so the mod directory is the archive root, exposes it as `packages.default`,
  and a matching app copies the zip into the game's mod directory. A second mod
  means a second zip derivation and a second install app.
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

## Conventions

* Everything is tab-indented: Nix, Lua, and `mod.json`.
* Markdown uses `*` for bullets.
* Only Nix formatting is enforced, so run `my-nix-format-all` before committing.
* The flake inputs both `follows` nixpkgs, so pin bumps go through
  `flake.lock`, not per-input nixpkgs versions.
* `open_files.txt` records the editor session's open files; it is not a build
  input.

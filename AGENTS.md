# Agent instructions

Crypt of the NecroDancer is a rhythm-based roguelike where movement, combat, and
survival happen to the beat. Its Synchrony version adds full Lua modding
support.

This repo has two halves, each with its own `AGENTS.md` covering the details:

* `DocDownloader/` mirrors the official Synchrony API documentation and renders
  it to Markdown and man pages.
* `Mods/` builds the Synchrony mods themselves, and consumes those rendered
  docs as its API reference.

## Commands

* `my-nix-format-all` formats all `.nix` files; `my-nix-format --check FILE`
  verifies a single one.
* `build-release` runs `nix flake check` and the nix formatting check.

## Conventions

* Nix is indented with eight spaces, applied by `my-nix-format-all`; do not
  hand-manage it. Lua and `mod.json` are tab-indented.
* Markdown uses `*` for bullets.
* Flake inputs `follows` nixpkgs, so pin bumps go through `flake.lock` rather
  than per-input nixpkgs versions.
* `open_files.txt` records the editor session's open files; it is not a build
  input.

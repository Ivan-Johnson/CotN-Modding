# AuthoredDocs

Holds the docs written by hand (`Src/`), and builds the docs tree that
publishes them beside the official docs and the game data. Why `mandb` is indexed in a
second derivation: `Docs/Adr/0002-*` at the repo root.

## Commands

* Validate with `nix flake check`, which runs `check-docs.bash` over the built
  tree.
* `nix build .#docs` builds the docs tree into `result/docs/`.
* `man-crypt` (dev shell) rebuilds the docs and runs `man` against them, e.g.
  `man-crypt necro.game.object.Map` or `man-crypt -k map`; the build includes
  a `mandb` index, so searching works. It is for humans.

## Architecture

* `docs-tree.nix` is the one module that owns the layout of `result/docs/`
  (the docs tree): `raw/`, `official/{minimal-html,markdown,man}/`,
  `authored/` and `game-data/`. The flake pins the CotN-docs mirror's
  `mainline` branch (the output of a `production` crawl) and its `game-data`
  branch as inputs. It takes DocDownloader's `converted` output,
  the mirror and the game data as inputs, adds the `mandb` index, and copies
  `Src/` verbatim into `authored/`. Change the layout there, and update the
  readers of it (`check-docs.bash`, `Mods/AGENTS.md`).
* `flake-module.nix` exposes the docs tree as the `docs` package, runs
  `check-docs.bash` over it as the `corpus` check, and defines `man-crypt`
  in the dev shell.
* Add a new authored doc to `Src/` and link it from `Src/README.md`, the
  index that `Mods/AGENTS.md` points at.

## Conventions

* `check-docs.bash` asserts over a whole build, catching what two-page fixtures
  cannot. Each assertion is paired with a guard against passing over nothing,
  since a check that silently examines no files looks exactly like one that
  passes.
* `htmlq --pretty` reflows the `minimal-html` tree onto its own lines, so an
  assertion over it must match within a single line: `<h1>Home` matches where
  `<h1>Home</h1>` does not.
* A player page states conclusions only. A claim's scope (the character, the
  mode) bounds it; the experiment's setup and trial counts belong in the commit
  message and the tests, and a claim that could not be concluded is left out.
  Open questions go to the issue tracker.
* Every claim on a player page has a test in `Mods/HelloWorld/`. Check a claim
  that an enemy never does something on enemies that come with the level, not
  only spawned ones.
* To document a game mechanic, use the `cotn-document-mechanic` skill.

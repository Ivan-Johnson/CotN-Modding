# AuthoredDocs

Holds the docs written by hand (`docs/`), and builds the docs tree that
publishes them beside the official docs and the game data. See the repo-root
`AGENTS.md` for shared commands and conventions. Why `mandb` is indexed in a
second derivation: `Docs/Adr/0002-*` at the repo root.

## Commands

* Validate with `nix flake check`, which runs `check-docs.bash` over the built
  tree.
* `nix build .#docs` builds the docs tree into `result/docs/`.
* `man-crypt` (dev shell) rebuilds the docs and runs `man` against them; it is
  for humans.

## Architecture

* `docs-tree.nix` is the one module that owns the layout of `result/docs/`
  (the docs tree): `raw/`, `official/{minimal-html,markdown,man}/`,
  `authored/` and `game-data/`. It takes DocDownloader's `converted` output,
  the mirror and the game data as inputs, adds the `mandb` index, and copies
  `docs/` verbatim into `authored/`. Change the layout there, and update the
  readers of it (`check-docs.bash`, `Mods/AGENTS.md`).
* Add a new authored doc to `docs/` and link it from `docs/README.md`, the
  index that `Mods/AGENTS.md` points at.

## Conventions

* `check-docs.bash` asserts over a whole build, catching what two-page fixtures
  cannot. Each assertion is paired with a guard against passing over nothing,
  since a check that silently examines no files looks exactly like one that
  passes.
* `htmlq --pretty` reflows the `minimal-html` tree onto its own lines, so an
  assertion over it must match within a single line: `<h1>Home` matches where
  `<h1>Home</h1>` does not.

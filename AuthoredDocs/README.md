# Summary

The docs written by hand for this repo (`docs/`, start at its `README.md`), and
the Nix module that builds the docs tree: `raw/`,
`official/{minimal-html,markdown,man}/`, `authored/` and `game-data/`.

## Building the docs with Nix

The flake takes the CotN-docs mirror as an input (the `mainline` branch, i.e.
the output of a `production` crawl, and the `game-data` branch), and
`docs-tree.nix` builds the docs tree from them.

```bash
nix build
```

The dev shell provides `man-crypt`, which rebuilds the docs and then runs `man`
against them. The build includes a `mandb` index, so searching works too:

```bash
man-crypt necro.game.object.Map
man-crypt -k map
```

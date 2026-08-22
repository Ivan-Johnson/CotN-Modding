# Copilot instructions

## Commands

- Build the generated Markdown tree with `nix build` (equivalently,
  `nix build .#markdown`). The `result` symlink points to a store path containing
  `minimal-html/` and `markdown/`.
- Evaluate all flake outputs without building them with
  `nix flake check --no-build`.
- Check both Bash scripts for syntax errors with
  `bash -n crawl-and-push.bash html-to-markdown.bash`.
- The dev shell provides `nixfmt`; format `flake.nix` with
  `nix develop -c nixfmt flake.nix`. There is no configured `nix fmt` formatter.

## Architecture

This repository is a two-stage documentation mirroring pipeline:

1. `crawl-and-push.bash` crawls the official Crypt of the NecroDancer modding
   documentation into `output/1-original-html.tar.gz`, then creates a temporary
   Git repository containing the crawl plus provenance files and pushes it to
   the separate private `Ivan-Johnson/CotN-docs` mirror.
2. `html-to-markdown.bash SRC_DIR DST_DIR` is the local transformation stage.
   It extracts each page's `<article>` into `DST_DIR/minimal-html/`, then uses
   Pandoc to produce the parallel `DST_DIR/markdown/` tree.
3. `flake.nix` pins the `CotN-docs` mirror as a non-flake input and packages the
   second stage. The default package and `.#markdown` are the same derivation.
   After publishing a production crawl, update that input with
   `nix flake update cotn-docs`.

`output/`, the local `CotN-docs/` checkout, and the `result` symlink are ignored
generated state, not source files.

## Repository conventions

- Both scripts use strict Bash mode (`set -euo pipefail`), quoted paths, and
  read-only configuration. Keep behavior in functions rather than introducing
  another task runner.
- `BUILD_MODE` defaults to `debug`: it crawls a small URL subset and pushes the
  mirror's `debug` branch. `BUILD_MODE=production` crawls the full site, takes
  about an hour, and pushes `mainline`.
- Do not run `crawl-and-push.bash` as a routine build or validation command. It
  always re-crawls the website and its final stage performs a real Git push.
- Crawl filtering is centralized in `ACCEPT_REGEX_DEBUG`,
  `ACCEPT_REGEX_PRODUCTION`, and `REJECT_REGEX`. Preserve the explicit rejected
  malformed events URL unless the upstream link is known to be fixed.
- HTML conversion processes only `*.html` files, in `LC_ALL=C` sorted order,
  while preserving relative directories. Markdown output collapses
  `foo/index.html` to `foo.md`, but keeps a top-level `index.html` as
  `index.md`.
- Keep the Pandoc output dialect in the single `PANDOC_TO` constant; changing it
  affects every generated Markdown page.
- The crawl tarball is made read-only after creation. Crawl logs are appended to
  `output/1-original-html.tar.gz.log`.
- The temporary clone used for publishing is intentionally retained so failed
  or surprising pushes can be inspected. It also records this repository's
  HEAD, diff, status, and a timestamp in the mirror commit.
- The private flake input is fetched over GitHub SSH. A build may require an SSH
  key with access when the pinned input is not already available locally.

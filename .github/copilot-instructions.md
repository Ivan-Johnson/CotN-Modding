# Copilot instructions

## Commands

- Build the generated docs with `nix build` (equivalently, `nix build .#markdown`
  or `nix build .#man`; all three are the same derivation). The `result` symlink
  points to a store path containing `minimal-html/`, `markdown/`, and
  `share/man/man3/`.
- Evaluate all flake outputs without building them with
  `nix flake check --no-build`.
- Print the store path of the pinned raw crawl, which is what the conversion
  reads and what its output has to be compared against, with
  `nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.cotn-docs.outPath'`.
- Check both Bash scripts for syntax errors with
  `bash -n crawl-and-push.bash html-to-docs.bash`.
- Run the conversion tests with `nix develop -c ./test-html-to-docs.bash`. They
  build tiny throwaway crawls, so they finish in seconds.
- The dev shell provides `nixfmt`; format `flake.nix` with
  `nix develop -c nixfmt flake.nix`. There is no configured `nix fmt` formatter.

## Architecture

This repository is a two-stage documentation mirroring pipeline:

1. `crawl-and-push.bash` crawls the official Crypt of the NecroDancer modding
   documentation into `output/1-original-html.tar.gz`, then creates a temporary
   Git repository containing the crawl plus provenance files and pushes it to
   the separate private `Ivan-Johnson/CotN-docs` mirror.
2. `html-to-docs.bash SRC_DIR DST_DIR` is the local transformation stage.
   It extracts each page's `<article>` into `DST_DIR/minimal-html/`, then uses
   Pandoc to produce the parallel `DST_DIR/markdown/` tree and the flat
   `DST_DIR/share/man/man3/` tree.
3. `flake.nix` pins the `CotN-docs` mirror as a non-flake input and packages the
   second stage. The default package, `.#markdown`, and `.#man` are the same
   derivation, and the dev shell's `man-crypt` builds it on demand to read a
   page.

`output/`, the local `CotN-docs/` checkout, and the `result` symlink are ignored
generated state, not source files.

## Repository conventions

- Both scripts use strict Bash mode (`set -euo pipefail`), quoted paths, and
  read-only configuration. Keep behavior in functions rather than introducing
  another task runner. Note that `set -e` does not fire inside the subshell of
  a command substitution, so `list_pages` propagates assertion failures to
  `run_pass` by hand rather than relying on `errexit`.
- `BUILD_MODE` defaults to `debug`: it crawls a small URL subset and pushes the
  mirror's `debug` branch. `BUILD_MODE=production` crawls the full site, takes
  about an hour, and pushes `mainline`.
- Do not run `crawl-and-push.bash` as a routine build or validation command. It
  always re-crawls the website and its final stage performs a real Git push.
- Crawl filtering is centralized in `ACCEPT_REGEX_DEBUG`,
  `ACCEPT_REGEX_PRODUCTION`, and `REJECT_REGEX`. Preserve the explicit rejected
  malformed events URL unless the upstream link is known to be fixed.
- HTML conversion processes only `*.html` files, in `LC_ALL=C` sorted order.
  The crawl mirrors a page reachable at `foo` as both `foo.html` and
  `foo/index.html`; `list_pages` drops the former so every page is converted
  exactly once. The two copies are never byte-identical, because each has its
  relative links written from its own directory, so `assert_same_page` compares
  them only after normalizing that depth away, and hard-fails on any other
  difference. The HTML and Markdown trees preserve relative directories, and
  Markdown output collapses `foo/index.html` to `foo.md` while keeping a
  top-level `index.html` as `index.md`.
- Both renames above move a page relative to the links pointing at it, so
  `rewrite_links` resolves each link back to the page it names and respells it
  for the tree being written. `run_pass` publishes the pass's pages in
  `page_set` so that a link out of the crawl can be told apart and left alone.
- Man pages are flat and unprefixed in section 3, named after the page (e.g.
  `necro.game.object.Map.3`). Upstream page names are fully qualified and
  unique; `to_man` hard-fails on a name collision rather than clobbering.
- Keep the Pandoc output dialect in the single `PANDOC_TO` constant; changing it
  affects every generated Markdown page. Man pages are converted straight from
  `minimal-html`, not from the Markdown, so they are unaffected by `PANDOC_TO`.
- The crawl tarball is made read-only after creation. Crawl logs are appended to
  `output/1-original-html.tar.gz.log`.
- The temporary clone used for publishing is intentionally retained so failed
  or surprising pushes can be inspected. It also records this repository's
  HEAD, diff, status, and a timestamp in the mirror commit.
- The private flake input is fetched over GitHub SSH. A build may require an SSH
  key with access when the pinned input is not already available locally.
- `test-html-to-docs.bash` generates its fixtures rather than committing them,
  so each case and its near-miss variants stay side by side. When adding a
  behavior, add a case that fails without it; the existing cases are known to
  fail if the dedupe, the page assertion, either of its error propagations, the
  man collision check, the man section, the `index.html` collapse guard, the
  headerlink removal, or either half of the link rewriting is removed.

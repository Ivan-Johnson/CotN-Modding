# Copilot instructions

## Commands

- `nix build` builds the docs. `result` holds `minimal-html/`, `markdown/`,
  `share/man/man3/`, and the `share/man/index.db` that `apropos` searches.
  `default` is the only package.
- `nix flake check` is the one validation command: it evaluates every output,
  syntax checks all three scripts, and runs the conversion tests. The tests
  build tiny throwaway crawls, so it finishes in seconds.
- `nix develop -c ./test-html-to-docs.bash` runs just the tests, and prints
  their output directly rather than through a build log.
- The pinned raw crawl, which is what the conversion reads and what its output
  has to be compared against:
  `nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.cotn-docs.outPath'`
- Do **not** run `crawl-and-push.bash` to build or validate anything. It always
  re-crawls the website, and its final stage performs a real Git push.
- `flake.nix` is tab indented and not `nixfmt` clean, so running the dev shell's
  `nixfmt` over it rewrites the whole file.

## Architecture

1. `crawl-and-push.bash` crawls the official docs into
   `output/1-original-html.tar.gz` and pushes it, with provenance files, to the
   private `Ivan-Johnson/CotN-docs` mirror. `BUILD_MODE=debug` (the default)
   takes a small subset and pushes the `debug` branch; `production` takes
   everything, runs about an hour, and pushes `mainline`.
2. `html-to-docs.bash SRC_DIR DST_DIR` extracts each page's `<article>` into
   `DST_DIR/minimal-html/`, then converts that into `DST_DIR/markdown/` and
   `DST_DIR/share/man/man3/`.
3. `flake.nix` pins the mirror as a non-flake input and packages stage 2. The
   dev shell's `man-crypt` builds it on demand and runs `man` against it.

## Conventions

- Strict Bash, quoted paths, `readonly` config, behavior in functions rather
  than another task runner. `set -e` does not fire inside the subshell of a
  command substitution, so `list_pages` propagates failures to `run_pass` by
  hand.
- The crawl mirrors a page reachable at `foo` as both `foo.html` and
  `foo/index.html`, and `list_pages` keeps only the latter. The two are never
  byte-identical, since each has its links written from its own directory, so
  `assert_same_page` compares them with that depth normalized away and
  hard-fails on any other difference.
- Markdown collapses `foo/index.html` to `foo.md`, keeping a top-level
  `index.html` as `index.md`. That and the dedupe both move a page relative to
  the links pointing at it, so `rewrite_links` resolves each link back to the
  page it names and respells it for the tree being written; `page_set` is how a
  link out of the crawl is told apart and left alone.
- Man pages are flat and unprefixed in section 3, named after the page (e.g.
  `necro.game.object.Map.3`). `to_man` hard-fails on a name collision rather
  than clobbering.
- Every man page needs `.SH NAME`, or `whatis` and `apropos` index nothing. It
  comes from the page's first `<h1>`, via Pandoc's `header-includes`.
  `page_summary` hard-fails on a page with no heading, so the tests'
  `write_page` supplies one and `write_raw_page` opts out.
- `flake.nix` builds the `mandb` index, because the pages are read-only once
  they reach the store. It needs a `MANDB_MAP` line; given only a
  `MANDATORY_MANPATH`, `mandb` reports an empty search path and silently
  creates nothing.
- `PANDOC_TO` is the single Markdown dialect knob. Man pages are converted from
  `minimal-html` rather than the Markdown, so it does not affect them.
- Preserve the explicitly rejected malformed events URL in `REJECT_REGEX`
  unless the upstream link is known to be fixed.
- The publishing clone is deliberately left behind so surprising pushes can be
  inspected.
- The private flake input is fetched over GitHub SSH, so a build can need a key
  with access when the pinned input is not already local.
- `test-html-to-docs.bash` generates its fixtures rather than committing them.
  When adding a behavior, add a case that fails without it.

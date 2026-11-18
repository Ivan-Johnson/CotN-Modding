# DocDownloader

Mirrors the official Synchrony API documentation and renders it to Markdown and
man pages. See the repo-root `AGENTS.md` for shared commands and conventions.
Why the crawl is mirrored rather than built, and why `mandb` is indexed in a
second derivation: `Docs/Adr/0001-*` and `0002-*` at the repo root.

## Commands

* Publish a fresh mirror with `BUILD_MODE=production
  DocDownloader/crawl-and-push.bash`. `BUILD_MODE` defaults to `debug` to
  spare the official webserver. `crawl-and-push.bash` always re-crawls and its
  final stage performs a real Git push, so reserve it for publishing a mirror.
* Validate with `nix flake check`, which runs `test-html-to-docs.bash`.
  `push-to-mirror.bash` is shared with the GameData context, which pushes the
  `game-data` branch; see `Docs/Adr/0005-*`.

## Architecture

1. `crawl-and-push.bash` crawls the official docs into
   `output/1-original-html.tar.gz` and pushes it to the `CotN-docs` mirror.
   `BUILD_MODE=debug` (the default) takes a small subset and pushes the `debug`
   branch; `production` takes everything, runs about an hour, and pushes
   `mainline`.
2. `html-to-docs.bash SRC_DIR DST_DIR` extracts each page's `<article>` into
   `DST_DIR/minimal-html/`, then converts that into `DST_DIR/markdown/` and
   `DST_DIR/share/man/man3/`.
3. `flake-module.nix` runs stage 2 over the pinned mirror and exports the
   result as `converted`, which the AuthoredDocs context assembles into the
   docs tree.

## Conventions

* Strict Bash, quoted paths, `readonly` config, behavior in functions rather
  than another task runner. The reasoning behind each converter step lives in
  comments beside it in `html-to-docs.bash`.
* Every man page needs `.SH NAME`, or `whatis` and `apropos` index nothing, so
  a page with no `<h1>` hard-fails. The tests' `write_page` supplies a heading
  and `write_raw_page` opts out.
* Preserve the explicitly rejected malformed events URL in `REJECT_REGEX`
  unless the upstream link is known to be fixed.

## Tests

* `test-html-to-docs.bash` generates its fixtures rather than committing them.
  When adding a behavior, add a case that fails without it.

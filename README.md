# Summary

This repo contains the scripts that update [my CotN-docs
repo](https://github.com/Ivan-Johnson/CotN-docs).

In order to push an update to that repo, all you need to do is:

```bash
BUILD_MODE=production ./crawl-and-push.bash
```

## Technical Details

There are two scripts:

* `./crawl-and-push.bash`

  1. Crawls [the official Crypt of the Necrodancer (CotN) modding
     documentation](https://vortexbuffer.com/synchrony/docs/index.html) into
     `output/1-original-html.tar.gz`.

  2. Pushes that raw HTML to the CotN-docs mirror.

* `./html-to-markdown.bash SRC_DIR DST_DIR`

  Converts every `*.html` file under `SRC_DIR` into markdown. Both output trees
  mirror `SRC_DIR`'s directory structure:

  1. Preprocesses the HTML into `DST_DIR/minimal-html/`.

  2. Converts that into `DST_DIR/markdown/`.

  Nothing currently publishes the markdown; it is only produced locally.

## Building the markdown with Nix

The flake takes the CotN-docs mirror as an input (the `mainline` branch, i.e.
the output of a `production` crawl) and runs `./html-to-markdown.bash` over it:

```bash
nix build
```

The result is a store path containing `minimal-html/` and `markdown/`.

The mirror is a private repo, so the input is fetched over SSH; you need a
GitHub SSH key that can read it. The pinned revision lives in `flake.lock`, so
after pushing a fresh crawl you have to run `nix flake update cotn-docs` to pick
it up.

## Extra Info

`./crawl-and-push.bash` always re-crawls from scratch, which takes about an hour
in production mode. In order to avoid hitting the official webserver too hard,
it defaults to crawling only a tiny subset of the official docs and pushing the
result to the `debug` branch of the mirror.

Set `BUILD_MODE` to pick a mode:

| `BUILD_MODE` | Crawls        | Mirror branch |
| ------------ | ------------- | ------------- |
| `debug`      | a tiny subset | `debug`       |
| `production` | everything    | `mainline`    |

`BUILD_MODE` defaults to `debug`.

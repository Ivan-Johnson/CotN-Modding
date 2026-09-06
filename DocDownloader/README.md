# Summary

This repo contains the scripts that update [my CotN-docs
repo](https://github.com/Ivan-Johnson/CotN-docs).

In order to push an update to that repo, all you need to do is:

```bash
BUILD_MODE=production ./crawl-and-push.bash
```

## Technical Details

There are two scripts:

* `./crawl-and-push.bash` crawls [the official Crypt of the Necrodancer (CotN)
  modding documentation](https://vortexbuffer.com/synchrony/docs/index.html)
  into `output/1-original-html.tar.gz`, then pushes that raw HTML to the
  CotN-docs mirror.

  It always re-crawls from scratch, which takes about an hour in production
  mode. To avoid hitting the official webserver too hard, `BUILD_MODE` defaults
  to `debug`:

  | `BUILD_MODE` | Crawls        | Mirror branch |
  | ------------ | ------------- | ------------- |
  | `debug`      | a tiny subset | `debug`       |
  | `production` | everything    | `mainline`    |

* `./html-to-docs.bash SRC_DIR DST_DIR` generates markdown and man-page docs
  from the HTML.

## Building the docs with Nix

The flake takes the CotN-docs mirror as an input (the `mainline` branch, i.e.
the output of a `production` crawl) and runs `./html-to-docs.bash` over it:

```bash
nix build
```

The dev shell provides `man-crypt`, which rebuilds the docs and then runs `man`
against them. The build includes a `mandb` index, so searching works too:

```bash
man-crypt necro.game.object.Map
man-crypt -k map
```

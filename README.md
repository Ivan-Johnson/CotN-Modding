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

* `./html-to-markdown.bash`

  1. Reads `output/1-original-html.tar.gz`.

  2. Preprocesses the HTML into `output/2-minimal-html.tar.gz`.

  3. Converts the HTML to markdown in `output/3-html-to-markdown.tar.gz`.

  Nothing currently publishes the markdown; it is only produced locally.

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

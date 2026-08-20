# Summary

This repo contains the scripts that update [my CotN-docs
repo](https://github.com/Ivan-Johnson/CotN-docs).

In order to push an update to that repo, all you need to do is:

```bash
trash output
BUILD_MODE=production make deploy
```

## Technical Details

Internally, this is what happens when you run `make deploy`:

1. `make output/1-original-html.tar.gz`: Crawl [the official Crypt of the
   Necrodancer (CotN) modding
   documentation](https://vortexbuffer.com/synchrony/docs/index.html).

2. `make output/2-minimal-html.tar.gz`: Preprocess the HTML

3. `make output/3-html-to-markdown.tar.gz` (or `make all`): Convert the HTML to
   markdown

4. `make deploy`: Push an update to the CotN-docs mirror

## Extra Info

The `Makefile` makes a few concessions in order to avoid hitting the official
webserver too hard:

* `make clean` does NOT delete `output/1-original-html.tar.gz`. If you want to
  re-download the original HTML files, then you'll need to delete that tarball
  manually.

* By default these scripts will only crawl a tiny subset of the official docs.

  In order to download everything, you'll need to run:

  ```bash
  BUILD_MODE=production make all
  ```

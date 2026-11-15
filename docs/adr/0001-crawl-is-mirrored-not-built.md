# The docs crawl is mirrored to a private repo, not run by the Nix build

Crawling the official docs takes about an hour and needs the network, so it
cannot run inside a reproducible Nix build. `crawl-and-push.bash` crawls
separately and pushes the tarball, with provenance files, to the private
`Ivan-Johnson/CotN-docs` mirror. The flake pins that mirror as a non-flake
input, and the build only converts the pinned HTML offline.

## Consequences

* The mirror is fetched over GitHub SSH, so a build can need a key with access
  when the pinned input is not already local.
* `crawl-and-push.bash` always re-crawls and really pushes, so it is never a
  validation step.
* The publishing clone is left behind on purpose, so a surprising push can be
  inspected.

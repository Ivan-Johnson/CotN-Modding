# The `mandb` index is built by a second derivation

`mandb` records each page's mtime in `index.db`, and Nix normalizes mtimes only
after a builder exits. Indexing inside the conversion derivation would
therefore bake in unnormalized mtimes and rebuild a different index every time.
The flake instead indexes in a second derivation over the first's output, where
the pages are already normalized and the index is reproducible. This also
suits the pages being read-only in the store.

## Consequences

* `mandb` needs a `MANDB_MAP` line. Given only a `MANDATORY_MANPATH` it reports
  an empty search path and silently creates nothing.

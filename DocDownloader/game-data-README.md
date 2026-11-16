# Crypt of the NecroDancer game data

Data scraped out of a running copy of the game by the ScrapeGameData mod. It is
published here so it can be read without owning or launching the game.

## Possible licensing risk

This is the game's own data (for example `necrodancer.xml`), and it may be
proprietary. Nobody has checked whether publishing it is allowed. Treat this
branch as private until that is settled.

This lives on its own branch, apart from the crawl of the public docs, so that
either can later be made public without the other.

## Contents

* `necrodancer.xml`, `component-defaults.json`, `entity-prototypes.json`,
  `script-files.json` and `versions.json`: the scraped datasets.
* `scrape-dir.txt`: the name of the local scrape these came from.
* `git_HEAD.txt`, `git_diff.txt`, `git_status.txt` and `timestamp.txt`: the
  state of the publishing repo, and when the push happened.

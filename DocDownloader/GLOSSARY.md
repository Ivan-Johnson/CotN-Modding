# DocDownloader

Vocabulary for mirroring the official Synchrony API documentation and
rendering it to Markdown and man pages.

## Language

**Mirror**:
The `CotN-docs` repo holding a crawl of the official docs on its `mainline`
branch, which the flake pins. Its `game-data` branch holds the game data.
_Avoid_: Cache, snapshot

**Raw docs**:
The official HTML exactly as crawled into the mirror.
_Avoid_: Original docs

**Official docs**:
The Markdown and man pages cleaned from the raw docs.
_Avoid_: Rendered docs, Docs (alone), output

**Authored docs**:
Docs written by hand for this repo, as opposed to derived from the official
docs or the game.

**Docs tree**:
The layout of `result/docs/`, which holds the raw docs, official docs, game
data, and authored docs together.

**Page**:
One document of the crawl, named by its path.
_Avoid_: File, document

**Page name**:
The flat, directory-free name a page is published under: `foo.html` and
`foo/index.html` are both `foo`.
_Avoid_: Slug, basename

**Duplicate pages**:
The `foo.html` and `foo/index.html` copies of one page. Only the latter is
converted.

**Page set**:
Every page in the crawl, used to tell links between pages from links out of the
crawl.

**Minimal HTML**:
A page's extracted `<article>`; the Markdown and man pages are both converted
from it.
_Avoid_: Cleaned HTML

**Navigation page**:
The sidebar navigation harvested from the landing page and published as its own
page, `cotn-docs`.
_Avoid_: Sidebar, TOC

**Scrape**:
One run of the ScrapeGameData mod in the live game, saved as a timestamped
directory of datasets.
_Avoid_: Dump, export

**Game data**:
The datasets a scrape reads out of the game itself, as opposed to the official
docs. Published to the mirror's `game-data` branch.
_Avoid_: Scraped docs

# DocDownloader

Vocabulary for mirroring the official Synchrony API documentation and
rendering it to Markdown and man pages.

## Language

**Mirror**:
The `CotN-docs` repo holding a crawl of the official docs, which the flake pins.
_Avoid_: Cache, snapshot

**Rendered docs**:
The Markdown tree and man pages built from the mirror.
_Avoid_: Docs (alone), output

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

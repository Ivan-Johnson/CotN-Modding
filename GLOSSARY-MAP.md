# Glossary Map

## Contexts

* [Mods](./Mods/GLOSSARY.md): the Synchrony API and game concepts that mods are
  written against
* [DocDownloader](./DocDownloader/GLOSSARY.md): mirroring the official Synchrony
  docs and rendering them
* [GameData](./GameData/GLOSSARY.md): scraping data out of the live game and
  publishing it to the docs mirror
* [AuthoredDocs](./AuthoredDocs/GLOSSARY.md): the docs written by hand, and the
  docs tree that publishes them beside the official docs and the game data

## Relationships

* **GameData → Mods**: the ScrapeGameData mod in `Mods/` is the source of the
  data.
* **GameData → DocDownloader**: GameData publishes to DocDownloader's mirror,
  sharing its push mechanism.

* **DocDownloader → AuthoredDocs**: DocDownloader's converted official docs go
  into the docs tree that AuthoredDocs builds.
* **GameData → AuthoredDocs**: the game data goes into the docs tree too.
* **AuthoredDocs → Mods**: the docs tree is the API reference that the Mods
  glossary is derived from, and the authored docs are guides for writing
  mods.

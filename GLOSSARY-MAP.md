# Glossary Map

## Contexts

* [Mods](./Mods/GLOSSARY.md): the Synchrony API and game concepts that mods are
  written against
* [DocDownloader](./DocDownloader/GLOSSARY.md): mirroring the official Synchrony
  docs and rendering them
* [GameData](./GameData/GLOSSARY.md): scraping data out of the live game and
  publishing it to the docs mirror

## Relationships

* **GameData → Mods**: the ScrapeGameData mod in `Mods/` is the source of the
  data.
* **GameData → DocDownloader**: GameData publishes to DocDownloader's mirror,
  sharing its push mechanism.

* **DocDownloader → Mods**: DocDownloader's docs tree is the API reference
  that the Mods glossary is derived from.

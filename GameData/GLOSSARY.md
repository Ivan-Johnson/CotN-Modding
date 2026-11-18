# GameData

Vocabulary for reading data out of the running game and publishing it to the
docs mirror.

## Language

**Scrape**:
One run of the ScrapeGameData mod in the live game, saved as a timestamped
directory of datasets.
_Avoid_: Dump, export

**Game data**:
The datasets a scrape reads out of the game itself, as opposed to the official
docs. Published to the mirror's `game-data` branch.
_Avoid_: Scraped docs

**Dataset**:
One file a scrape produces, such as `necrodancer.xml`.
_Avoid_: Output file

**Chunk**:
One base64 piece of a dataset, emitted by the mod as a log line and
reassembled into the dataset afterwards.
_Avoid_: Part, fragment

# GameData

Scrapes data out of the running game with the `ScrapeGameData` mod (which
lives in `Mods/`) and publishes it to the `game-data` branch of
the docs mirror. See `Docs/Adr/0005-*` for why the data has its own branch.

## Commands

* `nix run .#scrape-game-data` runs the mod in the live game and saves the
  reassembled datasets under `Tmp/scrape-game-data/<timestamp>/`. It is
  impure: it needs a running, native Steam/Proton CotN.
* `nix run .#push-game-data -- [SCRAPE_DIR]` pushes a scrape (the newest by
  default) to the mirror. It is a real Git push, so never use it to validate.
* Validate with `nix flake check`, which runs `test-reassemble.bash` and
  `test-push.bash`.

## Architecture

1. The mod logs each dataset as base64 chunks
   (`[ScrapeGameData] DATA <name> <index>/<total> <chunk>`) to
   `NecroDancer.log`, its only output channel.
2. `reassemble-scrape.bash` rebuilds the datasets from that log.
3. `push-game-data.bash` checks the scrape is complete and error-free, then
   hands it to `DocDownloader/push-to-mirror.bash`.

The chunk line format is a contract between the mod and
`reassemble-scrape.bash`; change both together, and `test-reassemble.bash`.
`flake-module.nix` runs the scrape through `liveGameRun` from the Mods
module, which locks the game for it (ADR 0009).


## Glossary

@GLOSSARY.md

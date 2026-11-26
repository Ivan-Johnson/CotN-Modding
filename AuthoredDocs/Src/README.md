# Authored docs

Index of the docs written by hand for this repo. Each page says whether it is
for players or for mod authors; read the one whose trigger matches your task.

## Mod authors

* [gotchas.md](./gotchas.md): Lua errors at load time, event ordering,
  `Tick.delay`, or stairs markers.
* [testing.md](./testing.md): writing or debugging tests, or a mod that does
  not reload.
* [game-data-sources.md](./game-data-sources.md): which game data a running
  mod can read (`GameXML`, `FileIO`, versions), which APIs fail, or
  reverse-engineering an entity's behavior with `print(ev)`.
* [synchrony-game-control.md](./synchrony-game-control.md): getting data out
  of a mod, running code in a turn, snapshot and restore, level changes,
  tiles, and spawning or converting entities.
* [enemy-ai-ids.md](./enemy-ai-ids.md): an enemy's `ai.id` and the components
  behind its movement.

## Players

A wiki of linked pages about the game's things, for Cadence.

* [controls.md](./controls.md): what each input does (moving, bumping, facing,
  items, spells, bombs, idling) and what a failed action costs.
* [enemies.md](./enemies.md): any zone one enemy, with a page per type and the
  stats tables; start here for enemies.
* [minibosses.md](./minibosses.md) and [king-conga.md](./king-conga.md): the
  stairs guards and the 1-4 boss fight.
* [coin-multiplier.md](./coin-multiplier.md): gold per kill and what breaks the
  chain.
* [bombs.md](./bombs.md), [digging.md](./digging.md),
  [traps.md](./traps.md), [shrines.md](./shrines.md): the level's tools and
  hazards.
* [weapons.md](./weapons.md), [action-items.md](./action-items.md),
  [chests-and-loot.md](./chests-and-loot.md): what the player can pick up and
  use.
* [stairs-and-levels.md](./stairs-and-levels.md): leaving a level, trapdoors
  and the boss level.
* [shops.md](./shops.md): prices, buying, and the shopkeeper.
* [cadence.md](./cadence.md) and [dove.md](./dove.md): the characters.

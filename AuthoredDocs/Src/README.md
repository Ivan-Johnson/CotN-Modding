# Authored docs

Index of the docs written by hand for this repo. Each page says whether it is
for players or for mod authors; read the one whose trigger matches your task.

## Mod authors

* [gotchas.md](./gotchas.md): Lua errors at load time, event ordering,
  `Tick.delay`, or stairs markers.
* [testing.md](./testing.md): writing or debugging tests, an effect that
  seems not to happen in no-beat mode, or a mod that does not reload.
* [game-data-sources.md](./game-data-sources.md): which game data a running
  mod can read (`GameXML`, `FileIO`, versions), which APIs fail, or
  reverse-engineering an entity's behavior with `print(ev)`.
* [synchrony-game-control.md](./synchrony-game-control.md): getting data out
  of a mod, running code in a turn, snapshot and restore, level changes,
  tiles, and spawning or converting entities.
* [enemy-ai-ids.md](./enemy-ai-ids.md): an enemy's `ai.id` and the components
  behind its movement.
* [replays.md](./replays.md): where the game saves replays and how that
  directory is laid out.

## Players

A wiki of linked pages about the game's things, for Cadence.

* [zone-one.md](./zone-one.md): the hub for zone one, the whole of a
  single-zone run; start here when unsure which page covers something.
  Zones two to five of an all-zones run: [zone-two.md](./zone-two.md),
  [zone-three.md](./zone-three.md), [zone-four.md](./zone-four.md),
  [zone-five.md](./zone-five.md).
* [controls.md](./controls.md): what each input does (moving, bumping, facing,
  items, spells, bombs, idling) and what a failed action costs.
* [enemies.md](./enemies.md): any zone one enemy, with a page per type and the
  stats tables; start here for enemies.
* [minibosses.md](./minibosses.md) and [king-conga.md](./king-conga.md): the
  stairs guards and the 1-4 boss fight.
* [coin-multiplier.md](./coin-multiplier.md): gold per kill and what breaks the
  chain.
* [damage.md](./damage.md): what a hit costs, what armor and invincibility
  stop, and how much your hits deal.
* [bombs.md](./bombs.md), [digging.md](./digging.md),
  [traps.md](./traps.md), [shrines.md](./shrines.md): the level's tools and
  hazards.
* [weapons.md](./weapons.md), [action-items.md](./action-items.md),
  [chests-and-loot.md](./chests-and-loot.md): what the player can pick up and
  use.
* [stairs-and-levels.md](./stairs-and-levels.md): leaving a level, trapdoors
  and the boss level.
* [sub-beat-timing.md](./sub-beat-timing.md): when within a beat a press
  counts, trap fuses, and the stairs' descent; dodging spikes with food or
  the heal spell, and free heals on the stairs.
* [all-zones-mode.md](./all-zones-mode.md): the five-zone run, its bosses and
  its starting kit.
* [shops.md](./shops.md): prices, buying, and the shopkeeper.
* [secret-shops.md](./secret-shops.md): cracked walls, the travel rune, and
  where each secret room appears.
* [food-shop.md](./food-shop.md): the secret food shop, its food and heart
  container prices, and its bomb-throwing shopkeeper.
* [conjurer.md](./conjurer.md): the Conjurer's secret room, where gold buys
  a random item for a chosen slot.
* [blood-shop.md](./blood-shop.md): the secret shop that sells for health, and
  its shopkeeper.
* [transmogrifier.md](./transmogrifier.md): the secret room that swaps an
  item for a random new one, its price and its slot tiles.
* [cadence.md](./cadence.md) and [dove.md](./dove.md): the characters.

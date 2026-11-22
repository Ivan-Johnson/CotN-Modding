# Controlling a running game from a mod

For mod authors. How a mod gets data out of the game, runs code at the right
moment, and changes game state. Everything here holds on CotN 4.2.1 with
Synchrony API 4.2.1, unless a bullet bounds it further.

## Getting data in and out

* A mod cannot write files: `FileIO` has no write function, `io` and `os` are
  absent, and `Storage`, `HTTP`, `DebugDump` and `LocalProxy` fail with
  "Permission denied".
* `print()` goes to `NecroDancer.log`. The game flushes the log about once a
  second, so a reader sees a line 0 to 1 s late.
* A mod can read a file inside a mounted mod's directory with
  `FileIO.exists` and `FileIO.readFileToString("mods/<Bundle>/<Mod>/cmd.txt")`.
  A directory without a `mod.json` is invisible to `FileIO`.
* `readFileToString` returns nil if the file is rewritten while the mod reads
  it. Guard for nil, and have the writer write a temp file and rename it.
* `event.tick.add(name, {order = "invokeLater"}, fn)` fires over 1000 times a
  second, so a `FileIO.exists` check per tick is cheap.
* A new global throws at load time. Keep state in `local`s; a reload resets
  them.
* A log line of 17 KB was too long, so chunk big output (4,000-character
  base64 lines carried a 250 KB string intact; see `ScrapeGameData`).
* `%q` can emit invalid JSON escapes, so serialize by hand. An entity dump
  contained a byte (0xa6) that is not valid UTF-8.

## Running code in a turn

* `event.turn.add(name, {order = "customActions"}, fn)` runs in a turn, where
  `Object.spawn` and `Object.convert` are documented as safe. Spawning from
  `event.tick` also works, but the entity keeps `spawnInvincibility` until the
  next turn; clear `spawnInvincibility.active` to remove it.
* Turns do not fire on their own. `Turn.getCurrentTurnID()` advances only when
  an action is simulated, so code queued for a turn waits until an input
  arrives. The `IDLE` input that forces a turn drops the groove chain.
* Changes made from `event.tick` persist, but a rollback discards any change
  made outside an action: after `Rollback.perform`, a spawn made that way was
  gone. A change that must survive has to travel as an action with args.
* In real-time rhythm `turnID` rises by about 30 per second even with no
  input, so it does not count beats.

## Snapshot and restore

* `Rollback.saveSnapshot(turnID)` then `Rollback.pinSnapshot(turnID)` keeps a
  snapshot of the current turn. Save explicitly: the snapshot the game took
  at the start of the turn predates anything changed since, so restoring it
  undid a `clear` done earlier in the same turn.
* `Rollback.perform(turnID)` and `Rollback.loadSnapshot(turnID)` both rewind,
  but the game then resimulates the player's actions from the action buffer
  and ends up where it began, minus changes made outside actions. Call
  `Rollback.loadSnapshot(turnID)`, then `ClientActionBuffer.clear()`, so
  nothing is replayed.
* Save a snapshot before an experiment that can kill the player (traps,
  angering a shopkeeper, a bomb beside you) and restore between trials. Each
  save overwrites the baseline a restore returns to, so save once, before
  the loop.
* Clearing the buffer drops the pinned snapshot, so save and pin it again;
  without that a second restore landed on an earlier turn. With it, one
  snapshot restored three times in a row. A spawn made after the snapshot is
  gone after a restore, and enemies cleared before it stay cleared.

## Input, runs and levels

* `Input.add(Action.Direction.RIGHT, 1)` moves player 1.
* `GameSession.start({mode = GameSession.Mode.SingleZone})` starts a run, even
  from a tick handler.
* A `levelGenerate` handler that sets `ev.options.seed` pins the level's
  layout: two runs with one seed gave identical tiles, another seed did not.
  The `Starting Single Zone run with seed` log line still shows a random
  number, so compare tiles. Entity ids differ between such runs, so match
  entities by type and tile.
* Inputs queued back to back made enemies skip a move about every 24 beats (a
  `Slime3`, which moves every beat, did so in 40 batched 8-beat runs and never
  in 49 beats sent one at a time); waiting 25 ticks after each input
  resolved stopped it and 10 did not. The cause is unknown. Deterministic
  enemies (`Slime2`, `Slime3`, `Skeleton`) act on the same beats either way.
* The diagonal inputs (`up_left` and the like) did nothing as Cadence on one
  1-1 level: the input never resolved and the turn did not advance. Tried
  once.
* No API steps N beats; `Turn.process(target)` did nothing. N `IDLE` inputs
  advance about one beat each, faster than real time.
* After an input that steps onto stairs or a `Trapdoor`, the level changes
  late (one stairs descent and one trapdoor fall, levels 1 and 2, no-beat
  mode):
  * The turn advances for the move itself, so the input's job finishes with
    the old level's state.
  * `event.levelComplete` fires afterwards: stairs 0.36 s, then `levelLoad`
    0.23 s later; trapdoor a `TRAPDOOR` groove-chain loss at 0.16 s,
    `levelComplete` at 2.2 s, `levelLoad` 0.25 s later. It is too late to
    warn the mod.
  * `LevelTransition.isPending()` stayed false throughout, so no API signals
    the change early. Reading state about 3 s later showed the new level.
  * Once, in a batch whose sixth action stepped onto a trapdoor, the three
    later actions all failed to move.

## Tiles and traps

* Walls and floor are tiles, not entities. `Tile.getInfo(x, y).name` is nil
  outside the level; `Tile.isSolid` tells wall from floor. Y grows downward:
  `up` moves to `y - 1`.
* `Tile.getInfo(x, y).digResistance` is 1 for `DirtWall`, 2 for `StoneWall`
  and 4 for a shop wall; a `LevelBorder` has none. Moving into a `DirtWall`
  digs it without moving, so a dug wall takes two actions. The basic shovel
  digs resistance 1 only (the stone and shop-wall cases follow from the
  numbers and were not tried).
* A door (`DoorVertical`, `DoorHorizontal`) is a solid wall with resistance
  -2. Moving into it opens it without moving, with no dig.
* `Marker.lookUpAll(Marker.Type.STAIRS)` lists the stairs as `{x, y}` (1 entry
  on a 1-1 level; locked and boss exits were not checked). No tile is named
  for the exit.
* `Tile.setType(x, y, "Floor")` turns a wall into floor, but entities attached
  to the wall (spike traps, wall torches) stay; delete the `*Wall*` entities
  too.
* A `Trapdoor` has the components `trap` and `trapDescend`; stepping on one
  drops the player to the next level. Spikes, bounce traps and tempo traps
  have `trap` without `trapDescend`. Enemies, the shopkeeper and `Crate`s
  have `health`; enemies and the shopkeeper also have `ai`.
* A `ShrineOfBlood` has collision mask 2 and no `ai`, `health`, `trap` or
  `item`; a `ChestLocked` matches that description too.

## Entities

* `Object.spawn(type, x, y)` takes absolute tile coordinates, not offsets from
  the player. Spawning into a wall succeeds and the enemy just sits there, so
  check the tile first.
* `Object.spawn(type, x, y)` and `Object.convert(entity, type)` work from tick
  and turn handlers; so does `Object.convertImmediately`. Converting to an
  unknown type does not throw; it logs `[Object] [warning] Invalid target type
  for conversion`.
* `Entities.despawn(id)` removes an entity at once but leaves it occupying its
  tile: an enemy later spawned beside it could never step there. Use
  `Object.delete(entity)`.
* Entities with a `position` include the player's inventory items (at the
  player's tile) and a `WallTorch` per wall: 49 plus 52 of those made the
  101 on a 1-1 level.
* A spawned enemy's `beatDelay.counter` starts at 0. With `beatDelay.interval`
  1 it acts every beat; with interval 2 it acts on beats 1, 3, 5, ... after
  the spawn. A dump taken after an action shows the counter at 0 again.
* Spawning or converting to `Dove` also attaches a `DoveHead` entity on the
  same tile.
* To dump an entity, loop over `Entities.listComponentNames()`, read
  `entity[name]`, and read the fields named in
  `Components.getComponentDefaults()[name]`. A dump is 12 to 17 KB (Cadence
  about 16.5 KB).

## Events about the player

* Hook the `object*` events (`objectGrooveChain`, `objectTakeDamage`,
  `objectDeath`, `objectSongEnd`). The `holder*` events run per inventory
  item: `holderGrooveChain` never fires for the player's multiplier.
* After a win or death the run-summary screen swallows every action.
  `RunSummary.getActiveSummary()` is truthy then. After dying on 1-1,
  `getPendingSummary`, `getActiveSummary` and `getDecisiveSummary` were all
  truthy (`victory` nil) while the player entity still existed; in normal play
  all three were false.

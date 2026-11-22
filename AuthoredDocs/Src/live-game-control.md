# Driving a live game from a mod

What a tracer-bullet POC for `AgentBridge` (issue #11) verified live on CotN
4.2.1. Anything not listed under "Unverified" was observed in the running game.

## Getting data in and out

* A mod cannot write files: `FileIO` has no write function, `io` and `os` are
  absent, and `Storage`, `HTTP`, `DebugDump` and `LocalProxy` fail with
  "Permission denied". `IPC` and `ServerSocket` load but are not a generic
  channel.
* Output goes through `print()` to `NecroDancer.log`. The game flushes the log
  about once a second, so an agent sees a response 0 to 1 s late.
* Input is a file the agent writes inside a mounted mod's directory
  (`FileIO.exists`, `FileIO.readFileToString("mods/<Bundle>/<Mod>/cmd.txt")`).
  A directory without a `mod.json` is invisible to `FileIO`.
* `install-mods` rsyncs with `--delete`, so a reinstall removes the file.
* `readFileToString` returns nil if the file is rewritten mid-poll; guard for
  it, and have the writer write a temp file and rename it.
* Poll from `event.tick.add(name, {order = "invokeLater"}, fn)`. It fires over
  1000 times a second, so a per-tick `FileIO.exists` is cheap.
* A new global throws at load time. Keep state in `local`s; a reload resets
  them.

## Running code in-turn

* `event.turn.add(name, {order = "customActions"}, fn)` runs in-turn, where
  `Object.spawn` and `Object.convert` are documented as safe. `AgentBridge`
  does not use it: the `IDLE` input it needs to make a turn fire drops the
  groove chain. Spawning from `event.tick` works too, but the entity keeps
  `spawnInvincibility` until the next turn, so clear `spawnInvincibility.active`.
* Turns do not fire on their own. `Turn.getCurrentTurnID()` advances only when
  an action is simulated, so a queued in-turn command waits until an input
  arrives.
* Mutating state from `event.tick` also applies and persists, but neither path
  survives rollback: after `Rollback.perform`, a spawn from a queued command
  was gone. Anything that must survive would have to travel as an action with
  args.

## Snapshot and restore

* `Rollback.saveSnapshot(turnID)` then `Rollback.pinSnapshot(turnID)` keeps a
  snapshot of the current turn. Save explicitly: the snapshot the game took at
  the start of the turn predates anything a bridge command changed since, so
  restoring it undid a `clear` done earlier in the same turn.
* `Rollback.perform(turnID)` and `Rollback.loadSnapshot(turnID)` both rewind,
  but the game then resimulates the player's actions from the action buffer
  and ends up where it began, minus mutations made outside actions. So
  `AgentBridge`'s `restore` calls `Rollback.loadSnapshot(turnID)`, then
  `ClientActionBuffer.clear()` so nothing is replayed.
* Clearing the buffer drops the pinned snapshot, so `restore` saves and pins
  it again; without that a second `restore` landed on an earlier turn. With
  it, the same snapshot restored three times in a row.
* Verified: a spawn made after the snapshot is gone after `restore`, and
  enemies cleared before it stay cleared.

## Driving the game

* `Input.add(Action.Direction.RIGHT, 1)` moves player 1.
* `GameSession.start({mode = GameSession.Mode.SingleZone})` starts a run, even
  from a tick handler.
* A `levelGenerate` handler that sets `ev.options.seed` pins the level's
  layout; `AgentBridge`'s `new-run seed=N` does this. Two runs with the same
  seed gave identical tiles, a different seed did not. The `Starting Single
  Zone run with seed` log line still shows a random number, so judge by the
  tiles.
* There is no "step N beats" API; `Turn.process(target)` did nothing. N
  `IDLE` inputs advance about one beat each, faster than real time.
* `AgentBridge` queues one input at a time and waits for
  `Turn.getCurrentTurnID()` to change before recording the outcome and queuing
  the next. In no-beat mode a turn resolves within a tick or so, so a batch of
  inputs costs one command round trip. It then waits 30 more ticks before the
  next input: with no wait, enemies skipped a move about every 24 beats (a
  Slime3, which moves every beat, did so in 40 batched 8-beat runs, and never
  in 49 beats sent one `idle` per command). 10 ticks still skipped; 25 did
  not. Walls and floor are tiles, not
  entities: comparing `Tile.getInfo(x, y).name` around the player before and
  after an input shows a dug wall.

* `agent-bridge` in the dev shell is a built copy of `Mods/agent-bridge.bash`;
  `install-mods` installs the mod from the source tree. After editing the
  script the CLI lacks the new commands until the shell is re-entered
  (`nix run .#agent-bridge --` runs the source meanwhile; a bare
  `bash Mods/agent-bridge.bash` lacks `wait_for_log`). The CLI compares
  a build-time hash of the script with the source and warns on a mismatch.

## Enemy cadence

* A spawned enemy's `beatDelay.counter` starts at 0, and an enemy with
  `beatDelay.interval` 1 acts every beat; with interval 2 (Skeleton, Slime2)
  it acts on beats 1, 3, 5, ... after the spawn. A dump taken after an action
  shows the counter at 0 again.
* Deterministic enemies (Slime2, Slime3, Skeleton) acted on the same beats
  whether the `idle`s were batched or sent one per command, once the settle
  wait above was in. Random movers (Zombie, Bat) vary run to run, so compare
  them with `scenario repeat=N`, never one trace against another.
* An enemy that never moves while `aggro.active` is true is probably
  blocked, not asleep: check the tiles and the entities around it first.

## Reading the map

* `AgentBridge`'s `map [N]` draws the tiles around the player: `Tile.isSolid`
  gives walls and floor, and `Tile.getInfo(x, y).name` is nil outside the
  level. No tile is named for the exit: its position comes from
  `Marker.lookUpAll(Marker.Type.STAIRS)` (`necro.game.tile.Marker`), a list of
  `{x, y}`. Y grows downward, as `up` moves to `y - 1`.
* The grid's top-left tile is `(x0, y0)` = the player's position minus the
  radius, so column C and row R are tile `(x0 + C, y0 + R)`; the CLI prints it
  in the header. Verified: a Skeleton at `(2,0)` showed at column 6, row 4 of
  a radius-4 map.
* Each entity type has one glyph, the same on every call and level. A table
  covers the common types; the rest get the first free letter of their name,
  remembered until the mod reloads (a reload may hand out different letters).
  Verified: `Skeleton` was `S` and `Skeleton2` `s` on levels 1 and 2 of one run.
* Entities with a `position` include the player's inventory items (at the
  player's tile) and a `WallTorch` per wall; `map` skips both, and so does
  `entities` unless it is given `type`, `component` or `id`, or `all=true`
  (the reply counts what it hid in `hidden`). Verified on a 1-1 level: 49
  shown plus 52 hidden equalled the 101 of `all=true`.

## Spawning and converting

* `Object.spawn(type, x, y)` and `Object.convert(entity, type)` work from both
  tick and turn handlers. `Object.convertImmediately` also works.
* Converting to an unknown type does not throw; it logs
  `[Object] [warning] Invalid target type for conversion`.
* `Entities.despawn(id)` removes an entity at once but leaves it occupying
  its tile: an enemy later spawned beside it could never step there (a
  Skeleton stayed put in every run after the first). `Object.delete(entity)`
  cleans up properly. `AgentBridge`'s `clear` uses it on every entity with an
  `ai` component (enemies and the shopkeeper), which leaves a level where only
  spawned enemies act.
* `Tile.setType(x, y, "Floor")` turns a wall into floor, with its tile
  properties. Entities attached to the wall (spike traps, wall torches) stay,
  so `AgentBridge`'s `clear arena=N` and `scenario ... arena=N` also delete
  the `*Wall*` entities within N tiles of the player.
* `AgentBridge`'s `scenario TYPE X Y ACTION...` runs a whole experiment on
  the current level in one call: it optionally clears the enemies, spawns,
  performs the actions and reports the spawned entity's chosen components
  before and after. Level layouts differ between runs, so use `arena=N` to
  turn the square within N tiles of the player into floor. `repeat=N` runs it
  N times from the same start (player teleported back with `Move.absolute`
  and healed, the enemy deleted) and replies with aggregates: step directions,
  moves per beat, first move, steps toward and away from the player.
* Spawning or converting to `Dove` also attaches a `DoveHead` entity on the
  same tile.
* `FamiliarDove` spawns as a world entity. Its use as an inventory item is
  untested.

## Events about the player

* Hook the `object*` events (`objectGrooveChain`, `objectTakeDamage`,
  `objectDeath`, `objectSongEnd`). The `holder*` events run per inventory
  item: `holderGrooveChain` never fires for the player's multiplier.

## Dumping an entity

* `AgentBridge`'s `entities show=@ai` dumps only the components that decide how
  an enemy moves and attacks (`ai`, `aiPattern`, `aiBasicSeek`, `beatDelay`,
  `aggro`, `activationRange`, `stasisAI`, `innateAttack`, ...), about 1 KB
  instead of 15 KB; `watch=@ai` does the same for `scenario`. Presets can be
  mixed with names: `show=@ai,grooveChain`.
* Replies are pure ASCII: bytes above 0x7f become `\u00XX` escapes, because a
  `show=all` dump held a byte (0xa6) that is not valid UTF-8 and broke JSON
  parsers. Non-ASCII text therefore reads as one code point per byte.

* Loop over `Entities.listComponentNames()`, read `entity[name]`, and read the
  fields named in `Components.getComponentDefaults()[name]`.
* A dump is 12 to 17 KB (Cadence about 16.5 KB). A log line took 17 KB, so cap
  per-line size and chunk base64, as `ScrapeGameData` does.
* `%q` can emit invalid JSON escapes; serialize by hand.

## Unverified

* Multiplayer and replay determinism.
* The lobby, character selection, and `GameSession.restart`.
* Custom actions with args (NecroEdit uses `Action.Special.NecroEdit_Cmd`).
* Why enemies skipped a move without a settle wait between inputs; the
  wait is a measured workaround, not an explanation.

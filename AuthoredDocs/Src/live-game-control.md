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

## Driving the game

* `Input.add(Action.Direction.RIGHT, 1)` moves player 1.
* `GameSession.start({mode = GameSession.Mode.SingleZone})` starts a run, even
  from a tick handler.
* There is no "step N beats" API; `Turn.process(target)` did nothing. N
  `IDLE` inputs advance about one beat each, faster than real time.
* `AgentBridge` queues one input at a time and waits for
  `Turn.getCurrentTurnID()` to change before recording the outcome and queuing
  the next. In no-beat mode a turn resolves within a tick or so, so a batch of
  inputs costs one command round trip. Walls and floor are tiles, not
  entities: comparing `Tile.getInfo(x, y).name` around the player before and
  after an input shows a dug wall.

## Spawning and converting

* `Object.spawn(type, x, y)` and `Object.convert(entity, type)` work from both
  tick and turn handlers. `Object.convertImmediately` also works.
* Converting to an unknown type does not throw; it logs
  `[Object] [warning] Invalid target type for conversion`.
* `Entities.despawn(id)` removes an entity at once, from a command handler.
  `AgentBridge`'s `clear` uses it on every entity with an `ai` component
  (enemies and the shopkeeper), which leaves a level where only spawned
  enemies act.
* Spawning or converting to `Dove` also attaches a `DoveHead` entity on the
  same tile.
* `FamiliarDove` spawns as a world entity. Its use as an inventory item is
  untested.

## Events about the player

* Hook the `object*` events (`objectGrooveChain`, `objectTakeDamage`,
  `objectDeath`, `objectSongEnd`). The `holder*` events run per inventory
  item: `holderGrooveChain` never fires for the player's multiplier.

## Dumping an entity

* Loop over `Entities.listComponentNames()`, read `entity[name]`, and read the
  fields named in `Components.getComponentDefaults()[name]`.
* A dump is 12 to 17 KB (Cadence about 16.5 KB). A log line took 17 KB, so cap
  per-line size and chunk base64, as `ScrapeGameData` does.
* `%q` can emit invalid JSON escapes; serialize by hand.

## Unverified

* Multiplayer and replay determinism.
* The lobby, character selection, and `GameSession.restart`.
* Custom actions with args (NecroEdit uses `Action.Special.NecroEdit_Cmd`).
* Whether enemies behave correctly under rapid `IDLE` inputs.

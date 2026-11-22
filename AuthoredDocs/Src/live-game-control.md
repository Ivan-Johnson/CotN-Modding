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
* The bridge's `input` accepts these names: `bomb`, `down`, `down_left`,
  `down_right`, `idle`, `item1`, `item2`, `left`, `right`, `spell1`, `spell2`,
  `throw`, `up`, `up_left`, `up_right`. `idle` is the no-op beat (there is no
  `wait`) and drops the groove chain. An unknown name makes the reply list
  these.
* The bridge's diagonal actions (`up_left` and the like) do nothing as
  Cadence: `input down_right` came back `TIMED-OUT` with no move and no turn
  passing (`turn` unchanged). Tried once, on a 1-1 level, as Cadence only.
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

## Pitfalls

* Never take a `snapshot` inside a test loop: each one overwrites the
  baseline that `restore` returns to. Take it once, before the loop.
* Never filter the likely killer (the boss, say) out of a loop's output. A
  `grep` that drops `KingConga` hides the entity that ends the run.
* After a multi-step `input`, read `at=` in the reply: a blocked move does not
  fail the batch, it silently shortens the path.
* `item1` activates an action item and `spell1` casts the spell.
* `restore N` replays deterministically: the same snapshot gives the same
  state each time (see "Snapshot and restore").

## Waiting for enemies

* To let enemies act, send `step N` (1 to 200) instead of a loop of `input
  idle` and `entities` calls: it is `input idle` N times in one command, and
  lists only the beats where something happened (the player moved, a tile
  changed, an entity within 12 tiles moved or died, or an event fired). Read the
  reply, then decide the next move.
* `repeat=N` and `watch=` are options of `scenario`, not of `input` or `step`.
  They repeat one spawned-enemy experiment and choose which of that enemy's
  components to report; they do not wait for natural enemies.

## Missing a beat, and ordering experiments

* In no-beat mode, an `idle` input drops the groove chain; that is what
  "missing a beat" means here. The other way to lose the chain, several
  actions in one beat, is believed impossible in no-beat mode (not tested).
* On a 1-4 King Conga run, a failed press at the throne (which logged
  `multiplier_lost(because=a failed action)`) was followed by the King leaving
  his throne; that is the one observation tying a missed beat to the fight.
* Run every boss-fight experiment before taking the exit stairs: killing the
  boss and descending ends the run, and the bridge's inputs time out at the
  run summary (`restore` still loads a snapshot, but no action is accepted).

## Level changes lag the reply

Tracer for holding an `input` reply until the next level loads (measured with
`print()` of the tick count in `levelComplete`, `levelLoad`, a per-tick
`LevelTransition.isPending()` and the job finish; one stairs descent and one
`Trapdoor` fall on levels 1 and 2, no beat mode):

* Verified: the job's turn ID advances for the move onto the stairs or
  trapdoor, so the reply comes after the usual 30-tick settle, not after
  `JOB_TIMEOUT_TICKS`. It describes the old level.
* Verified: `event.levelComplete` fires after that reply, not before it.
  Stairs: 0.36 s later, `levelLoad` 0.23 s after that. Trapdoor: a
  `TRAPDOOR` groove-chain loss 0.16 s later, `levelComplete` 2.2 s later,
  `levelLoad` 0.25 s after that. So it cannot tell the mod, in time, that a
  change is coming.
* Verified: `LevelTransition.isPending()` stayed false for the whole run,
  both times.
* So a `state` sent right after such an `input` can show the old level.
  Verified: after `sleep 3` it showed the new one. The mod has no early
  signal other than guessing from the player's tile (stairs marker, trapdoor
  entity), which no design chose; `Mods/AGENTS.md` tells the agent to wait.
* Observed once: in a batch whose sixth action stepped onto a trapdoor, the
  remaining three actions all reported `=` (no move). Keep the stairs or
  trapdoor step last in a batch.

## Routing

What the tracer for `AgentBridge`'s `route` verified on CotN 4.2.1, level 1-1
with seed 1 and basic-shovel Dove:

* Verified: moving into a `DirtWall` (`Tile.getInfo(x, y).digResistance` 1)
  digs it without moving, so a dug wall takes two actions. A `StoneWall` reads
  2 and a `LevelBorder` has no resistance; `route` never enters them. The
  stone and shop-wall (4) behaviour of the shovel was not tried; it is taken
  from the resistance numbers.
* Verified: a door (`DoorVertical`, `DoorHorizontal`) is a solid wall with
  resistance -2; moving into it opens it without moving, so it also takes two
  actions, and needs no `dig=true`.
* Verified: a spawned `Trapdoor` has the components `trap` and `trapDescend`;
  stepping on one dropped the player to the next level. Spikes, bounce traps
  and tempo traps have `trap` without `trapDescend`. Enemies, the shopkeeper
  and `Crate`s have `health`; enemies and the shopkeeper also have `ai`.
  `route` refuses `trapDescend` tiles and shopkeepers, charges 3 for tiles
  with `ai` or `health` (moving into them attacks), and 5 for other traps. A
  route that had to cross two trapdoors was reported unreachable.
* Verified: `route` does not know `ShrineOfBlood` (collision mask 2, no `ai`,
  `health` or `trap`), so it plans straight through one. Walking `route
  stairs` into it on a 1-1 level cost 10 health in one action (see
  [zone-one-cadence.md](./zone-one-cadence.md#shrines)). Look at the `map`
  legend and `entities` before running a route you cannot afford to lose.
* Verified: scanning every tile of a 1-1 level (24 by 42, 1,008 tiles) with
  `Tile.getInfo` in one command added no time that showed against the
  roughly 1 s round trip. Bigger levels were not measured.
* Verified: `Marker.lookUpAll(Marker.Type.STAIRS)` returned one entry on
  1-1. Whether locked or boss exits are listed was not checked.
* Verified: `agent-bridge input $(agent-bridge route stairs dig=true)` ended
  on the stairs tile after `clear`. Untested: chests (`ChestLocked` has
  collision mask 2 and neither `ai` nor `health`, so `route` treats it as
  floor).

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
  Once a type finds no free letter it gets `?`, so on a busy level several
  types share `?`: on one 1-3 `Wraith`, `Dragon2`, `Trapdoor`, `Crate3`, and
  more all showed as `?`, and on a 1-4 `Deathmetal`, `PreBossBarrier`,
  `BossLight` and `Dragon2` did. Read the legend, or use `entities`, for those.
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

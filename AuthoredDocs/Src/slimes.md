# Slimes

For players. Slime, Slime2 and Slime3. Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Movement |
|------|-------|----|--------|----------|
| `Slime` | 1 | 1 | 100 | stationary |
| `Slime2` | 2 | 2 | 2 | bounces down and up |
| `Slime3` | 1 | 1 | 1 | clockwise 4-tile loop |

* `Slime` never moves or attacks. It did nothing in 8 beats even when
  adjacent to the player, so its damage of 100 never fired (`guess` on what
  it would do). One dagger hit kills it.
* `Slime2` bounces down, then up, one tile every second beat, wherever the
  player is. Which direction it starts with depends on the spawn tile. A move
  into a wall is skipped and it goes the other way: spawned at (0,2) with a
  wall below, it went up first. If the player is in its path it stops and
  attacks for 2 every second beat. After a dagger hit it carries on with the
  bounce: the first hit moved it from (1,0) to (1,1), which is its normal
  move, not knockback.
* `Slime3` walks a 4-tile loop on every beat: right, down, left, up, so
  clockwise on screen. Its starting corner depends on the spawn tile: from
  (1,1) it went right first, from (2,2) next to a wall it went left first. If
  the player is on its next step it stays put and attacks for 1 every second
  beat.
* `Slime2` and `Slime3` start at a loop position that is the same for the
  same tile and differs between tiles; what decides it is not known.
* Both loop slimes act on the same beats whether the player's idles are sent
  one at a time or in a batch (`Slime3` moved on 40 of 40 batched beats and
  `Slime2` on 20 of 20).

Gold per kill: [coin-multiplier.md](./coin-multiplier.md). Mod-author names for
the movement codes: [enemy-ai-ids.md](./enemy-ai-ids.md).

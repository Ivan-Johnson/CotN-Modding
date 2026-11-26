# Slimes

For players. The green `Slime`, blue `Slime2` and orange `Slime3`. Stats
columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Slime` (green) | never acts | 1 | none | 1 |
| `Slime2` (blue) | 2 | 2 | 2 | 2 |
| `Slime3` (orange) | 1 | 1 | 1 | 1 |

A slime walks a fixed loop whatever you do, and only hurts you if you stand on
its loop.

* **Green.** A `Slime` never moves or attacks, even when you stand next to it.
* **Blue.** A `Slime2` bounces down one tile, then back up, moving every second
  beat: down on the first beat, up on the third, and so on.
* **Orange.** A `Slime3` walks a square, one step every beat: right, down,
  left, up, so clockwise.
* **Walls.** When a slime appears, it starts its loop at the first move whose
  whole loop is clear of walls, checking every tile of the loop. So a `Slime2`
  with a wall below bounces up first, and a `Slime3` with a wall to its right,
  or diagonally down and right, steps down first. A slime with no clear loop
  never moves. The loop is fixed from then on: a wall that appears on it later
  stops the slime in front of the wall, and it does not pick a new loop.
* **Enemies in the way.** A slime whose next tile holds another enemy waits
  until the tile is free, then carries on with the same step.
* **Attacking.** A slime whose next move is onto you stays put and hits you
  instead: a `Slime2` for 2 on its beats, a `Slime3` for 1 every second beat,
  although it moves every beat. Once you step off its loop it carries on. A
  slime next to you but with you off its loop never hits you.
* **Hits.** A hit never knocks a slime back. A `Slime2` that survives a hit
  carries on bouncing, even on the beat it is hit.
* The slimes a level starts with walk the same loops.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md#gold-per-kill).
Mod-author names for the movement codes: [enemy-ai-ids.md](./enemy-ai-ids.md).

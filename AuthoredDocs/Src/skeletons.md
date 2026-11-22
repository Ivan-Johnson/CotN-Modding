# Skeletons

For players. Skeleton, Skeleton2, Skeleton3 and their headless variants. How
these were measured: [enemies.md](./enemies.md).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Skeleton` | 2 | 1 | 1 | 1 |
| `Skeleton2` | 2 | 2 | 3 | 2 |
| `Skeleton3` | 2 | 3 | 4 | 3 |

* All three seek the player, one tile every second beat, x first and then y.
  Next to the player they attack every second beat. Which beat they first move
  on depends on the spawn timing.
* `Skeleton2` kills a 12-health player in four hits and `Skeleton3` in three.
* A dagger hit turns `Skeleton2` (first hit) and `Skeleton3` (second hit) into
  `Skeleton2Headless` and `Skeleton3Headless`, shoved one tile away along the
  hit direction. The first hit on `Skeleton3` changed nothing visible.
* A headless skeleton does not seek, but it charges: after a dagger hit on a
  natural `Skeleton2`, the `Skeleton2Headless` was shoved one tile, then ran
  one tile every beat in the direction of the hit, away from the player,
  until a wall stopped it. It stayed there for the 8 beats watched and never
  attacked. When another enemy stood right behind it, it was not shoved or
  moved, and a second hit killed it. A spawned one, or one hit with a wall
  behind it, stood still. Only `Skeleton2` was seen this way; `Skeleton3` is
  untested.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md).

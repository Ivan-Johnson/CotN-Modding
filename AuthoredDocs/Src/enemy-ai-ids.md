# Enemy AI codes

For mod authors. The `ai.id` component field picks an enemy's movement style,
and `ai.directions` holds direction codes: 1 is right, 3 up, 5 left, 7 down,
and 2, 4, 6 and 8 are the diagonals. Read from zone one enemy dumps on CotN
4.2.1.

| `ai.id` | Style | Types |
|---------|-------|-------|
| 0 | stationary | `Slime`, `Trapchest`, the `Headless` skeletons |
| 1 | straight line, reverses at an obstacle | `Zombie` |
| 2 | fixed loop (`aiPattern.moves`) | `Slime2`, `Slime3` |
| 3 | random walk | `Bat`, `Bat2`, `Bat3`, `BatMiniboss` |
| 7 | seeks the player | `Skeleton`, `Skeleton2`, `Skeleton3`, `Monkey`, `Monkey2`, `Ghost`, `Wraith`, `Dragon`, `Minotaur`, `Minotaur2` |

* `beatDelay.interval` is the number of beats between actions; the player-facing
  tables call it speed. A spawned enemy's `beatDelay.counter` starts at 0.
* Every type above has an `ai.directions` list and `aiBasicSeek`, whatever its
  `ai.id`.
* `activationRange.radius` is the straight-line distance within which a
  sleeping enemy wakes, through walls: 3 for most types, 7 for `Minotaur` and
  `Minotaur2`, 10 for `Dragon2`, none for `Dragon`. `Slime`, `Slime2`, `Slime3`
  and `Zombie` start with `aggro.active` true and never sleep; every other type
  starts with it false. A `Ghost` wakes by its own rule (see
  [ghost.md](./ghost.md)); the rest are in [enemies.md](./enemies.md).
* A spawned `Wraith` has `ai.id` 7 and never acts; a natural one chases.
* A headless skeleton has `ai.id` 0 but a `charge` component that makes it run.
* A `Ghost`'s `stasis.active` is true while the player faces or is beside it,
  which is the facing rule in [ghost.md](./ghost.md).
* A `Monkey`'s grab uses `grabParalyzeVictim`, `grabMoveOntoVictim` and
  `grabIncreaseHealth` (`multiplier` 4, `max` 4 on `Monkey`; `multiplier` 3,
  `max` 6 on `Monkey2`).
* `grooveChain` has `killsForInitMultiplier` 1, `killsPerMultiplier` 4 and
  `maximumMultiplier` 3.
* Miniboss entries come from `Sync_enemyPoolMiniboss`.

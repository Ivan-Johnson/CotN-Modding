# Coin multiplier and gold

For players. How kills turn into gold, measured as Cadence in no-beat mode on
CotN 4.2.1, from the player's `grooveChain` and `goldCounter`.

## The multiplier

* The multiplier starts at 1. It rises with consecutive kills: the first kill
  gave multiplier 2 and the fifth gave 3, which is the cap. (`grooveChain` has
  `killsForInitMultiplier` 1, `killsPerMultiplier` 4 and `maximumMultiplier`
  3, and `killCount` followed it.)
* The chain breaks (`multiplier_lost`, `killCount` back to 0) on:
  * an `idle` action, even in no-beat mode;
  * a failed action, such as moving into a wall;
  * taking damage: a `Minotaur` hit at x2 logged
    `multiplier_lost(because=taking damage)` in the same action.
* Moving to an empty tile does not break it.

## Gold per kill

A killed enemy leaves a `ResourceCoinN` entity on its tile; the player gets
the gold by walking onto it. `ResourceDiamond` entities in the entity list are
part of the level, not drops.

Gold at multiplier 1 (fresh run, no kills, one enemy spawned at (1,0) in a
cleared arena, killed with the dagger and its coin walked onto; the same on
every repeat):

| Type | Gold at x1 |
|------|-----------|
| `Slime`, `Zombie` | 2 |
| `Slime3`, `Skeleton`, `Bat` | 4 |
| `Skeleton2`, `Bat2` | 6 |
| `Skeleton3` | 8 |
| `Bat3` | 40 |

Six `Slime` kills in a row gave +2, +3, +3, +3, +3, +4 gold.

A fit for both measurements (`guess` for every type but `Slime`, the only one
seen above x1) is gold = base x (multiplier at the kill + 1), with the
multiplier before the kill's own increase, and a base of 1 for `Slime` and
`Zombie`, 2 for `Slime3`, `Skeleton` and `Bat`, 3 for `Skeleton2` and `Bat2`,
4 for `Skeleton3` and 20 for `Bat3`.

Not measured: `Slime2`, `Monkey2`, `Ghost` and `Wraith`. A `Trapchest` leaves
an item instead.

A bomb's blast destroys coins lying on its tiles; see [bombs.md](./bombs.md).

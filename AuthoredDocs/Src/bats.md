# Bats

For players. Bat, Bat2 and Bat3; the miniboss version is in
[minibosses.md](./minibosses.md). Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Directions |
|------|-------|----|--------|------------|
| `Bat` | 2 | 1 | 1 | 4 |
| `Bat2` | 1 | 1 | 2 | 4 |
| `Bat3` | 1 | 1 | 3 | 8, so diagonals appear |

* Bats take a random step with no bias toward the player: over about 330 steps
  across the three bats and `BatMiniboss`, 48 to 51% of steps got closer,
  which is chance.
* A bat attacks only when a random step lands on the player, and the hit takes
  the slot of a move. In 40 beats `Bat3` hit the player 2 to 4 times, `Bat2` 0
  to 2 times, and `Bat` 3 times in one trial and never in two.
* A step into a wall seems to be lost, so a bat sometimes skips a beat (`guess`;
  over 40 beats `Bat2` and `Bat3` moved 34 to 39 times).
* A `Bat2` that stepped into a trident's line was killed from 2 tiles away; see
  [weapons.md](./weapons.md).

Gold per kill: [coin-multiplier.md](./coin-multiplier.md).

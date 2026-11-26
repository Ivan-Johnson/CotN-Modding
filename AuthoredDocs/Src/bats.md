# Bats

For players. Bat, Bat2 and Bat3; the miniboss version is in
[minibosses.md](./minibosses.md). Stats columns:
[enemies.md](./enemies.md#stats-tables). What wakes a bat:
[enemies.md](./enemies.md#when-enemies-act).

| Type | Speed | HP | Damage | Directions |
|------|-------|----|--------|------------|
| `Bat` | 2 | 1 | 1 | 4 |
| `Bat2` | 1 | 1 | 2 | 4 |
| `Bat3` | 1 | 1 | 3 | 8, diagonals included |

* Almost every time a bat acts, it steps one tile to a random free
  neighbouring tile in one of its directions. The pick does not lean toward
  you or away from you.
* Walls and other enemies are never picked: a bat with one free neighbour
  always steps onto it, and a bat boxed in by walls and enemies stays put. It
  never attacks another enemy.
* Your tile counts as a free tile. When a bat picks it, the bat hits you from
  where it stands instead of moving. Next to you in the open, a `Bat` or
  `Bat2` hits on about a quarter of its actions and a `Bat3` on about an
  eighth; a `Bat3` hits diagonally too.
* A bat whose only free neighbour is your tile attacks every time it acts.
  No hit lands on the beat after a bat hits you, so even a `Bat2` or `Bat3`
  lands a hit only every second beat.
* The `Bat`s a level starts with move the same way: one tile up, down, left
  or right, every second beat.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md).

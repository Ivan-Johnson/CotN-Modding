# Minibosses

For players. The natural miniboss that guards a level's stairs; which one
appears differs between runs. Stats columns: [enemies.md](./enemies.md#stats-tables). What the stairs do when it dies:
[stairs-and-levels.md](./stairs-and-levels.md).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `BatMiniboss` | 2 | 2 | 3 | 2 |
| `Minotaur` | 1 | 3 | 4 | 3, or one bomb |
| `Minotaur2` | 1 | 5 | 5 | 5 |
| `Dragon` | 2 | 4 | 4 | 4, or one bomb |
| `Dragon2` | 2 | 6 | | 6 |

## BatMiniboss

* It moves like a [bat](./bats.md): random steps, one every second beat.
* Spawned, it did not attack in 40 beats. A natural one hit the player for 3
  on the beat the player stepped next to it, and two dagger hits killed it.

## Minotaur and Minotaur2

* A natural `Minotaur` started moving toward the player while the player was
  still 9 tiles away behind walls, one tile every beat. It digs through
  walls on the way; see [digging.md](./digging.md).
* Face to face with a dagger, a `Minotaur` hit once for 4 on the beat of the
  first dagger hit and not on the next two beats; the third hit killed it.
  That is one attack in three adjacent beats. One fight only.
* With `ArmorLeather` a `Minotaur` hit for 3 instead of 4 (once).
* The 1-3 stairs room held a `Minotaur2`, two `Skeleton2`, two `Skeleton3`, a
  `Ghost`, a `Bat`, a `Monkey2` and slimes, which were all still until the
  player came within 3 tiles of the corridor mouth. Then within 3 beats the
  `Minotaur2` dug through a `DirtWall` at (14,6) and stood adjacent.
* `Minotaur2` was not fought; whether it attacks as `Minotaur` does is
  unknown.

## Dragon and Dragon2

* A natural `Dragon` on a 1-1 stairs tile stayed put while the player walked
  up to about 3 tiles away and dug a wall toward it, then walked toward the
  player one tile every second beat.
* Fought with a dagger at the end of a one-tile corridor: the dragon stepped
  adjacent, the player hit it four times in a row, it hit once for 4 (on the
  second of those beats), and the fourth hit killed it. One fight; no fire or
  other ranged attack was seen.
* A bomb kills a `Dragon` without damage to the player; see
  [bombs.md](./bombs.md).
* A `FollowerSnowbro` on the dragon's tile blocks the player's melee; see
  [action-items.md](./action-items.md).
* `Dragon2` (a 1-3 stairs room and a 1-4 start room) was only seen, not
  fought.

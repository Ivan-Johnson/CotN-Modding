# Skeletons

For players. Skeleton, Skeleton2, Skeleton3 and their headless variants.
Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Skeleton` | 2 | 1 | 1 | 1 |
| `Skeleton2` | 2 | 2 | 3 | 2 |
| `Skeleton3` | 2 | 3 | 4 | 3 |

* **Chasing.** All three wake when you come within 3 tiles and then chase you
  one tile every second beat, as [enemies.md](./enemies.md#movement)
  describes. Next to you they hit every second beat.
* **Losing the head.** The hit that leaves a `Skeleton2` or `Skeleton3` on 1
  HP turns it into a `Skeleton2Headless` or `Skeleton3Headless`: the first
  dagger hit on a `Skeleton2`, the second on a `Skeleton3`. The first hit on
  a `Skeleton3` only costs it 1 HP; it keeps its head and stays where it is.
* **Headless charge.** The hit that knocks its head off shoves it one tile away
  from you. It then runs one tile every beat in the direction of the hit
  until a wall or another enemy stops it, and stands there from then on.
  With a wall or an enemy right behind it when it loses its head, it is not
  shoved and does not run.
* **Headless and harmless.** A headless skeleton never attacks, even when you
  stand next to it. One more hit kills it.
* Skeleton2s and Skeleton3s that come with the level lose their heads and
  charge the same way.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md).

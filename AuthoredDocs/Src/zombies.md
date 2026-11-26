# Zombie

For players. Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Zombie` | 2 | 1 | 2 | 1 |

A zombie walks back and forth along one straight line and never chases you.

* **Walking.** It starts facing up, down, left or right, at random, and steps
  one tile that way every second beat from the first beat of a level.
* **Turning.** When a wall, another enemy or a chest blocks its step, it spends
  that move turning round in place and walks back on its next move. So in a
  corridor n tiles long it makes n-1 moves, turns, and makes n-1 moves back.
  Two zombies that meet head-on both turn round.
* **Attacking.** It hits only when you stand on the next tile of its line:
  instead of stepping onto you it hits for 2, and again every second beat while
  you stay there. It never turns toward you, so beside its line or behind it you
  are safe, even next to it. Step off its line and it walks on the same way,
  through the tile you stood on.
* **Bounce traps** push it a tile sideways; it keeps walking the way it was.
* Zombies that come with the level follow the same rules.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md#gold-per-kill).

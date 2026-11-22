# Zombie

For players. How these were measured: [enemies.md](./enemies.md).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Zombie` | 2 | 1 | 2 | 1 |

* A `Zombie` walks in a straight line, one tile every second beat. Its
  initial direction is random (four directions were sampled from one tile),
  not toward the player.
* At a wall it pauses one move slot and turns round, so a corridor of n tiles
  gives n-1 moves, a pause, and n-1 moves back.
* It does not chase: it walked past a player standing one tile off its line.
* It attacks only when the player is next on its line: it stops and hits for 2
  every second beat. In 12 runs with a `Zombie` spawned beside the player,
  3 pointed at the player and hit twice in 4 beats (4 damage), and 9 walked
  away along another line and never attacked.
* Whether a `Zombie` can be hit while it walks, and how it reacts to another
  enemy in its way, are untested.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md).

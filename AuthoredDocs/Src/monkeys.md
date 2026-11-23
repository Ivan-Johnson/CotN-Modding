# Monkeys

For players. Monkey and Monkey2. How these were measured:
[enemies.md](./enemies.md).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Monkey` | 1 | 1 | 0 | 1, or 4 while grabbing |
| `Monkey2` | 1 | 2 | 0 | 2, or 6 while grabbing |

* Monkeys seek the player one tile every beat, x first, and step onto the
  player's tile. From 2 tiles away they were adjacent after beat 1 and on the
  player after beat 2. They deal no damage.
* A monkey on the player's tile has grabbed the player. Every move the player
  made was blocked and the dagger hit the monkey instead.
* Grabbing multiplies the monkey's health: `Monkey` goes from 1 to 4 and
  `Monkey2` from 2 to 6. A grabbing `Monkey` took 4 hits and a grabbing
  `Monkey2` took 6. A monkey hit before it grabs dies to its normal health.
  A first hit on a `Monkey2` moved it back one tile, and it came back.
* Nothing was stolen: the inventory was identical after each kill, and no coin
  was left when a monkey died on the player's tile.

Gold per kill: [coin-multiplier.md](./coin-multiplier.md), which also covers
what a grabbing monkey drops.

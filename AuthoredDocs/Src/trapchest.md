# Trapchest

For players. Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Trapchest` | 1 | 1 | 2 | 3 bumps |

* A `Trapchest` never moves.
* Bumping it once does nothing, the second bump deals 2 to the player, and the
  third kills it.
* It leaves a random item, not coins.

## Trapchest6 ("Shrine Mimic")

* A `Trapchest6` has 1 health and a speed-1 `ai`. It never moved.
* The first bump cost 2 health (`damage_taken source=Trapchest6`) and the
  second killed it, with a dagger that did 2 damage (Sunglasses worn): two
  bumps, not the three of `Trapchest`. One kill, so the count is unconfirmed.
* It leaves a random item; its pattern for weapons is in
  [weapons.md](./weapons.md).

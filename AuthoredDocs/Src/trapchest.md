# Trapchest

For players. How this was measured: [enemies.md](./enemies.md).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Trapchest` | 1 | 1 | 2 | 3 bumps |

* A `Trapchest` never moves.
* Bumping it once does nothing, the second bump deals 2 to the player, and the
  third kills it.
* It leaves a random item, not coins: `HeadSpikedEars`, `WeaponHarp` and
  `Torch1` in three tries.

## Trapchest6 ("Shrine Mimic")

* A `Trapchest6` has 1 health and a speed-1 `ai`. It never moved.
* The first bump cost 2 health (`damage_taken source=Trapchest6`) and the
  second killed it, with a dagger that did 2 damage (Sunglasses worn): two
  bumps, not the three of `Trapchest`. One kill, so the count is unconfirmed.
* It left `WeaponBlunderbuss`, which replaced the dagger when walked onto
  (the dagger stayed on the tile). The blunderbuss killed a `Slime2` and a
  `Crate` and hit a second `Slime2` for 3 each in one swing; its pattern is
  in [weapons.md](./weapons.md).

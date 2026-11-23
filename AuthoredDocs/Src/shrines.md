# Shrines

For players. Measured as Cadence in no-beat mode on CotN 4.2.1.

## ShrineOfBlood

* Seen in the middle of a 1-1 room. It is solid, and its hint reads "Give
  blood, get blood weapon".
* One `down` into it cost 10 health (`damage_taken(amount=10
  source=ShrineOfBlood)`, 12 to 1 in a single action), and the inventory then
  held a Blood weapon (a `Sync_WeaponBloodTrident` once, a Blood Staff once) instead of `WeaponDagger`. A `ShovelBlood` was
  listed on the tile below the shrine (whether it is a drop was not checked).
  The dagger entity stayed at the player's tile.
* The shrine stayed in place with `interactable.active` still true; a second
  use was not tried.

## Sync_ShrineOfFeast

* On 1-3 it listed `activeDrop` `FoodMagicCarrot`, `CharmGluttony` and
  `CharmFrost`, and `inactiveDrop` `Food2`.
* It stayed inactive: a bump from the left and from below only gave
  `multiplier_lost(because=a failed action)`. What activates it is unknown.

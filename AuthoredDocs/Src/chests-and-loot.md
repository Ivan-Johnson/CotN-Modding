# Chests and loot

For players. What the player found in chests and on the floor in single-zone
runs as Cadence, in no-beat mode on CotN 4.2.1. These are samples, not the
loot pools.

## Chests

* Bumping a `ChestBlack` opens it (`killed target=ChestBlack`). Seen drops:
  `Sync_WeaponOnyxDagger`, `ArmorLeather`, `FeetGlassSlippers`,
  `Sync_ShieldObsidian`, `Sync_WeaponTitaniumTrident` and
  `WeaponTitaniumBroadsword`.
* `ChestRed` gave `FamiliarIceSpirit`, `BloodDrum` and `HolyWater`. `ChestPurple` gave
  `SpellEarth`.
* `ChestLocked` opened by bumping it while holding a `MiscKey` (found
  on the floor 3 tiles from it); the key was used up and the chest dropped
  `HeadSunglasses`. Bumping it without a key was not tried.
* A route search that treated a chest as floor walked onto it and opened it.
* A weapon drop is swapped in for the current weapon when the player picks it
  up (`Sync_WeaponOnyxDagger` replaced `WeaponDagger`, whose entity then
  vanished). Armor and other drops lie on the chest's tile until the player
  walks onto them.
* What `ChestWhite` does is untested. A `Trapchest` is an enemy: see
  [trapchest.md](./trapchest.md).

## Equipment

* `ArmorLeather`: with it a `Minotaur` hit for 3 instead of 4 (once; other
  enemies untested).
* `FeetGlassSlippers` ("Ignore terrain, breakable") left the inventory after
  the player took damage.
* `HeadSunglasses` ("+1 dmg, strange vision"): the dagger did 2 damage
  instead of 1 while worn.
* `Sync_ShieldObsidian` is described as "Multiplier hit protection"; it was
  not tested.

For the weapons see [weapons.md](./weapons.md), and for `FamiliarIceSpirit`,
`BloodDrum` and `SpellEarth` see [action-items.md](./action-items.md).

## Crates

`Crate2` slides one tile away when the player walks into it, and a weapon hit
did `damage_dealt(amount=0)`, so melee does not break a crate. A bomb does;
see [bombs.md](./bombs.md).

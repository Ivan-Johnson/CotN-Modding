# Weapons

For players. Measured as Cadence in no-beat mode on CotN 4.2.1. Shrine
weapons: [shrines.md](./shrines.md); where weapons were found:
[chests-and-loot.md](./chests-and-loot.md).

* `WeaponDagger` hits the tile in front, 1 damage: kills take one hit per
  health point.
* `Sync_WeaponOnyxDagger` (damage 1, same reach as the dagger) has a combo:
  after a hit the combo is 1, and the next hit does 1000 damage. Any action
  that is not a hit resets it to 0.
  * From one snapshot against a `Minotaur` (3 HP): `right right` hit for 1
    then killed; `right idle right` and `right idle idle right` hit for 1 both
    times; `right left right` ended with combo 0.
  * A kill also sets the combo to 1, so the next target dies to its first hit:
    a `Skeleton` kill was followed by a one-hit `Bat`.
  * So an enemy with more than 1 HP costs two consecutive hits, not its HP in
    hits.
* `Sync_WeaponTitaniumTrident` (damage 2) hits up to 2 tiles in the facing
  direction: it killed a `Bat` 2 tiles away and a `Skeleton2` in one hit. It
  did nothing to a `Ghost` 1 or 2 tiles ahead while the player already faced
  it; the ghost died when it stepped adjacent and the player turned to it, as
  with the dagger.
* `WeaponTitaniumBroadsword` (damage 2, a 3-tile line) hits every enemy in
  the facing line: one swing killed a `Skeleton2` and hit a `Skeleton3` behind
  it, and another hit a `Bat` and a `Minotaur2` for 2 each. It killed a
  `Ghost`, `Zombie`, `Slime3` and `Wraith` in one hit each. An enemy 2 tiles
  away was not hit by a lone press: the player moved instead.

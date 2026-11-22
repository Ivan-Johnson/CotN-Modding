# Shops

For players. Measured as Cadence in no-beat mode on CotN 4.2.1, on one seeded
1-1 (seed 1) and earlier runs.

* A shop sits a few tiles from the start on 1-1 and another on 1-3, behind a
  `DoorHorizontal` in `ShopWall` (dig resistance 4; see
  [digging.md](./digging.md)). A `Shopkeeper` (9 health) stands at the back.
  Wares show a `PriceTagGold` (or `PriceTagHealth`).
* A 1-3 shop sold `Food4` for 65 gold, and a different one sold
  `Sync_WeaponOnyxBroadsword` (50), `MiscHeartContainer2` (200) and
  `TorchInfernal`. The 1-1 shop sold `WeaponObsidianDagger` (25, "Multiplier-based
  damage"), `MiscHeartContainerCursed` (25) and `ArmorLeather` (20). Another
  1-1 shop sold `Sync_ScrollBerzerk`, `RingProtection` and `WeaponGoldenDagger`
  for gold, and a second, health-priced one `WeaponGoldenStaff`,
  `MiscHeartContainerCursed` and `Food3`.
* Walking onto a ware buys it: with 25 gold, `ArmorLeather` left 5 and was
  equipped.
* With too little gold the move is blocked, silently: no event, no gold
  spent, and the player stays put. This blocks a route through the ware.
* `MiscHeartContainerCursed` gave `cursedHealth` 2 and left health at 12/12
  (bought from a shop whose keeper was already dead; see below).
* A bomb placed next to the wares destroys them
  (`killed by=BombLit target=WeaponObsidianDagger`), hurts the shopkeeper (4)
  and the player (3 with `ArmorLeather`, `source=Cadence`).
* Three dagger bumps on the `Shopkeeper` did nothing (its `aggro` turned
  active; it has `unrevealedDamageImmunity`, cause unconfirmed). After the
  bomb a dagger hit did 1 damage, and the shopkeeper hit back for 19,
  killing the player at 9 health. Do not anger it.
* A dead shopkeeper makes everything free: after a live run removed
  it (it has an `ai`), stepping onto `ArmorLeather`, the heart and the dagger
  cost no gold. That explained a first, wrong, "shops are free" result.

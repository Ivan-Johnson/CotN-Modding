# Dove

What a live dump of the Dove character showed, compared with Cadence's. These
are component values only; what each component does at runtime is not yet
verified. Gathered with `agent-bridge new-run Dove` and `agent-bridge entities
type=Dove show=all` (see `live-game-control.md`).

## The character

* The in-game description is "Dove mode: pacifism! You do no damage but exits
  are unlocked."
* Health is 14 (7 hearts), against Cadence's 12.
* `initialInventory` is `Bomb`, `WeaponFlower`, `ShovelCrystal` and
  `RingPeace`, against Cadence's `Bomb`, `WeaponDagger` and `ShovelBasic`.
* The character has a `DoveHead` attachment, as Cadence has `CadenceHead`.
* `playableCharacterUnlockable` requires completing zone 2.

## Components Cadence lacks

* **Pacifist traits:**
  * `traitInnatePeace` has `zoneMaxEnemies = [24, 20, 16, 24, 20]`.
  * `traitRemoveEnemies` has `count = 3`.
  * `traitSkipBosses`, `traitNoSarcophagus`, `traitNoTrapdoors`,
    `traitSmallerShops` and `traitBannedSecretRooms` have no fields.
  * `noNeedDamage` has no fields.
  * `bypassStairLock` has `level = 2`.
* **Enemies:** `enemyBans` lists `Harpy`, `Monkey`, `Monkey2`, `Monkey3`,
  `Monkey4` and `Sync_ShockMonkey`.
* **Items:**
  * `inventoryBannedItems` bans the `itemBanPacifist`, `itemBanNoDamage`,
    `itemBanShoplifter` and `itemBanWeaponlocked` components, plus shovels
    and shrines that carry pacifist or weapon-locked bans.
  * `inventoryCursedSlots` curses the weapon slot.
  * `inventoryBannedItemSlots` bans the ring slot for the same flags.
* **Bombs:** `teleportingBombs` (`suppressComponent = "enemy"`,
  `teleportFlags = 2`) fits the hint on the Dove familiar, "TELEPORT ENEMIES".
* **Other:** `shoplifter`, `progressionBonusHealth` (`health = 2`),
  `Sync_traitNoWallSpikes` and `Sync_traitCoopEnemySpawnReduction`
  (`reductionPercentage = 20`).

## Components that differ

* `songEndCast` is `SpellcastCowardice`; Cadence's is `SpellcastSongEnd`.
* `DynChar_dynamicCharacter.excludedItems` contains `WeaponFlower`, so the
  character sprite does not draw it.
* The `voice*` components use `dove*` sounds, with `voiceEnemyDeath`
  (`doveOhNo`) in place of Cadence's lack of one.

## Related entity types

`FamiliarDove`, `FollowerDove` and `SpellcastDoveHit` exist as entity types.
Only `FamiliarDove` has been seen: the game's XML defines it as an action-slot
familiar item with the hint "TELEPORT ENEMIES".

## Unverified

* What each trait component does at runtime, including whether `WeaponFlower`
  does no damage. One attack on an adjacent Skeleton left it at full health,
  but I did not confirm the attack was processed.
* What `SpellcastDoveHit` and `FollowerDove` do.

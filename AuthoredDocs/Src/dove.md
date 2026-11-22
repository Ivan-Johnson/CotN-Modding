# Dove

For players. What a live dump of the Dove character shows, compared with
Cadence ([cadence.md](./cadence.md)), on CotN 4.2.1. These are the character's
settings; what each does in play is mostly untested (see the end).

* The in-game description is "Dove mode: pacifism! You do no damage but exits
  are unlocked."
* Health is 14 (7 hearts), against Cadence's 12.
* The starting items are `Bomb`, `WeaponFlower`, `ShovelCrystal` and
  `RingPeace`, against Cadence's `Bomb`, `WeaponDagger` and `ShovelBasic`.
* The character requires completing zone 2 to unlock.
* The settings suggest these pacifist rules, by their names (unverified in
  play): bosses are skipped, there are no sarcophagi, trapdoors or secret
  rooms, shops are smaller, a stair lock is bypassed at level 2, and the
  enemy count is capped per zone (24, 20, 16, 24, 20) and 3 enemies are
  removed.
* Dove cannot have `Harpy`, `Monkey`, `Monkey2`, `Monkey3`, `Monkey4` or
  `Sync_ShockMonkey` enemies (`enemyBans`).
* Items with pacifist, no-damage, shoplifter or weapon-locked bans are
  banned, the weapon slot is cursed and the ring slot is banned for the same
  flags.
* The character's bombs teleport enemies (`teleportingBombs`), which matches
  the hint "TELEPORT ENEMIES" on `FamiliarDove`, an action-slot familiar item.
* Dove's song-end spell is `SpellcastCowardice`, not Cadence's `SpellcastSongEnd`.

## Untested

* Whether `WeaponFlower` does no damage: one attack on an adjacent `Skeleton`
  left it at full health, but it was not confirmed that the attack was
  processed.
* What `SpellcastDoveHit` and `FollowerDove` do, and what each pacifist rule
  does in a run (#42).

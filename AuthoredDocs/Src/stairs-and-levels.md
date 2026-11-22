# Stairs and levels

For players. How a single-zone run as Cadence moves through 1-1 to 1-4,
measured in no-beat mode on CotN 4.2.1. Levels are random: two runs put
different things near the start.

## Leaving a level

* Walking onto the stairs loads the next level a second or so later. The
  player starts at (0,0) on every level. Health, gold and the coin multiplier
  carry over.
* A miniboss usually stands on or by the stairs, and which one differs between
  runs; see [minibosses.md](./minibosses.md). A `Minotaur` on a 1-1 stairs woke
  up on its own, and the stairs worked once it was dead. On one run 1-2's
  stairs were plain `Stairs`; on another they were `LockedStairs` under a
  `BatMiniboss`, and killing it turned the tile into `Stairs` in the same
  action.
* Standing on a `LockedStairs` tile while its miniboss dies unlocks it and
  descends at once, with no further input.
* On 1-3 the stairs sat in a walled room with several enemies, including a
  `Minotaur2`; another run's 1-3 had a `Dragon2` on the stairs.
* A `Trapdoor` skips the stairs: on 1-3 one at (-1,9), plain floor to the
  `tile` command, took the player to 1-4. Another run's 1-3 had one at (10,1)
  behind a `DirtWall` and a `Ghost` in a one-tile cell; stepping on it loaded
  1-4 with health unchanged. Trapdoors were also listed on 1-1 and 1-2 (not
  stepped on), and their position is random.

## 1-4, the boss level

* The start room is closed (5 by 5 tiles in one run) with enemies inside, and
  the boss room is above it, entered through five `PreBossBarrier` at y = -7
  (x = -2 to 2).
* The first step past y = -7 sealed the entrance with `BossWall` at y = -6.
* The boss is random: `Fortissimole` (with 14 `Skeleton`s in two rows and four
  `Ghost`s), `Deathmetal` at (1,-11) (seven `BounceTrapOmni`) and `KingConga`
  were seen in three runs. Only [King Conga](./king-conga.md) was fought.

## Shops

A shop sits a few tiles from the start on 1-1 and another on 1-3. A 1-3 shop
sold `Food4` for 65 gold, and a different one sold `Sync_WeaponOnyxBroadsword`
(50), `MiscHeartContainer2` (200) and `TorchInfernal`; the player had 41 gold
and bought nothing. Shop walls are `ShopWall`, which the basic shovel cannot dig
(see [digging.md](./digging.md)).

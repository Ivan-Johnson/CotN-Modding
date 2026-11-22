# Single-zone zone one as Cadence

What a first exploration with `agent-bridge` found on CotN 4.2.1 (see
`live-game-control.md` for the bridge itself). Everything below was observed
live unless it is under "Unverified". Gathered with `agent-bridge new-run
Cadence`, then `state`, `entities`, `spawn`, `input` and `step`. Written
before the second-pass measurements; where this page and
[zone-one-enemies.md](zone-one-enemies.md) disagree, trust that page.

## What a run starts with

* The player is at (0, 0) with 12 health (`health` and `maxHealth`).
* The inventory holds `Bomb`, `WeaponDagger` and `ShovelBasic`, plus
  `AddchestBlack`, `AddchestRed`, `AddchestWhite`, `CoinsX15` and `CoinsX2`.
  The last five are not in Cadence's `initialInventory`; they appear to be a
  single-zone starting kit.
* The level is random. Two runs placed different things near the start, so
  compare numbers across runs with care.

## What a level contains

A zone-one level had about 80 entities with a position, mostly spread over a
region from roughly x = -13 to 14 and y = -8 to 18. The first run listed:

* **Enemies:** `Slime` (8), `Slime2` (8), `Skeleton` (3), `Monkey` (2), `Zombie`
  (1) and a `BatMiniboss`.
* **Shop:** a `Shopkeeper`, three `PriceTagGold` entities, `Food1`,
  `WeaponDaggerElectric` and a `HeadCrownOfGreed`, all within a few tiles.
* **Containers and pickups:** `ChestRed`, two `ChestPurple`, `Crate`, `Bomb`,
  `ResourceDiamond` and `MiscKey` (in a later run).
* **Traps:** `BombTrap`, `BounceTrapLeft`, `TempoUpTrap` and `Sync_WallSpike`.
* **Decoration:** 30 `WallTorch`.

Walls and floor are not entities, so `entities` cannot show the map; read them
with `agent-bridge tile X Y [X2 Y2]`. A start area showed `Floor` around the
player, with `DirtWall` (`digResistance` 1) and `StoneWall` (2) beyond.

A later run listed 111 entities with a position (the player's inventory items
sit at the player's tile and count). By type: `WallTorch` 40, `Skeleton` 10,
`Slime` 7, `Slime2` 6, `Monkey` 5, `PriceTagGold` 3, two each of `ChestRed`,
`TravelRune8`, `Sync_WallSpike` and `BounceTrapDown`, and a shop (`Shopkeeper`,
`Pawnbroker`, `TransactionTile*` for each equipment slot, `WeaponTitaniumDagger`,
`Food1`, `HeadCrownOfGreed`). It also had a `TorchWalls`, `TempoUpTrap` and
`ResourceDiamond`. Six `Skeleton`s sat in a 2 by 3 block at (4..5, 1..3), a few
tiles from the start.

## Enemy stats

Per-type health, damage, interval, movement and hits to kill are in
[zone-one-enemies.md](zone-one-enemies.md).

* `Slime2` showed `maxHealth` 4 in one early run; every later measurement
  gave 2.
* `Slime`'s damage of 100 is as read; I never let one hit me, so I do not know
  what it does in play.
* Dagger kills take one hit per health point: a spawned `Slime2` went from 2 to
  1 to dead over two `right` inputs.

## Behavior

* Enemies move only when you act in no-beat mode, and then each follows its
  own movement style, most of them not toward the player (see
  [zone-one-enemies.md](zone-one-enemies.md#movement-ai)). A spawned
  `Skeleton` or `Zombie` next to the player attacked at once.
* A spawned `Skeleton` placed at (3, 0) was adjacent (1, 0) after the one beat
  the spawn took. A spawned `Monkey` moved onto the player's tile. A spawned
  `Slime2` at (3, 0) did not move in three beats, probably its interval
  of 2 plus the spawn delay; the enemies page has its bounce.
* Moving into a `DirtWall` digs it with `ShovelBasic`: the first input leaves
  the player in place and turns the tile into `Floor` (confirmed with the
  `tile` command), and the next input walks through.
* A `StoneWall` (`digResistance` 2) never gave way to the basic shovel in three
  tries; a `DirtWall` has `digResistance` 1. The map's outer edge is
  `LevelBorder`, a solid wall with no `digResistance`.
* Earlier unpadded position sequences, where inputs sent back to back seemed to
  drop, were most likely dirt being dug rather than dropped inputs. The
  padded run (`step 1` around each input) is the one to trust.
* An input takes effect within about one second, as the `state` that follows it
  already shows the result.
* In real-time rhythm `turnID` rose by about 30 per second even with no input,
  so it is not a beat counter.

## Damage taken

The first run used real-time rhythm (still available as `new-run
rhythm=regular`), and one `step 1` sample cost 3 to 4 times
`innateAttack.damage`: `Zombie` (`damage` 2) took 12, 6, 0 and `Skeleton`
(`damage` 1) took 12, 8, 5, 1. Several beats passed between commands at about
1 s latency. `new-run` now uses no-beat mode (#18), and the same setup behaves:
a spawned `Skeleton` (`damage` 1, `interval` 2) took the player from 12 to 11,
11, 10, 10, 9, 9 over six `step 1` samples, i.e. its stated damage every second
step. A spawned `Zombie` beside the player did not attack in six steps; it
walks a straight line, and attacks only when the player is on its line.

In no-beat mode the song never ends, a beat cannot be missed, and enemies do
not come to you: time passes only when you act.

## Beyond the first level

A `new-run Cadence` is a `SingleZone` run that plays through 1-1 to 1-4. One
walk-through (no-beat mode, 12 health) found:

* Walking onto the stairs loads the next level after a second or so; `state`
  right after the move still shows the old level. The `level_loaded` event
  marks the switch. The player is at (0, 0) on every new level. Health,
  gold and the coin multiplier carry over.
* The `map` command prints `stairs at` for the exit, and the miniboss on it
  differs between runs. In one run (1-1) a `Minotaur` stood on it and woke up
  on its own; once it was dead the stairs worked. In another, a `Dragon` on
  1-1 and a `Minotaur` on 1-2 were the guards, and 1-2's stairs were plain
  `Stairs` (no `LockedStairs`). In the first run, on 1-2 the tile was
  `LockedStairs` under a `BatMiniboss`: killing the miniboss
  turned it into `Stairs` in the same action. On 1-3 the stairs sat in a
  walled room with a `Minotaur2`, a `Skeleton3`, two `Monkey2`, a `Ghost`,
  two `Bat` and others; it was not entered. A second run's 1-3 had a
  `Dragon2` on the stairs. `Dragon` and `Minotaur` fights are in
  [zone-one-enemies.md](zone-one-enemies.md).
* A `Trapdoor` on 1-3 (at (-1, 9), plain floor to `tile`) took the player to
  1-4 without touching the stairs. `Trapdoor` entities were also listed on 1-1
  and 1-2 (not stepped on), so it may be a way past a locked or guarded exit.
  A later run's 1-3 had one at (10, 1), 10 tiles from the start, behind a
  `DirtWall` and a `Ghost` in a one-tile cell; stepping on it loaded 1-4 with
  the player's health unchanged. The position is random.
* 1-4 is the boss level. The first run had a closed start room of 5 by 5
  tiles at the bottom, with a `Minotaur2`, `Skeleton3`, `Bat2` and `Ghost`
  inside, and above it the boss room with `Fortissimole`, 14 `Skeleton`s in
  two rows, four `Ghost`s and five `PreBossBarrier` entities across the
  entrance at y = -7. A later run had the same shape with a different cast:
  a start room with `Dragon2`, `Bat2`, `Skeleton3` and `Ghost`, a boss room
  with `Deathmetal` at (1, -11), no skeletons, seven `BounceTrapOmni` and
  five `PreBossBarrier` at y = -7, x = -2 to 2. The boss is random, and
  neither boss was fought.
* A third run's 1-4 had `KingConga` (2 health, `innateAttack.damage` 3) on a
  `KingCongaThrone` at (0, -17), two 8-snake `ZombieSnake` lines (1 health, damage
  2, interval 2, a `ZombieSnakeYellow` head each) at y = -16 and -17 on either
  side, two `Bat`, one `Bat2` and two `Ghost`. The start room was empty. The
  player walked in (2 health, `Sync_WeaponTitaniumTrident`); the first step
  past y = -7 sealed the entrance with `BossWall` at y = -6 and the snake
  heads headed down the room, one tile every 2nd beat.
  * The first press at the throne from the tile below gave
    `multiplier_lost(because=a failed action)`, and the king became
    `KingCongaAngry` (`ai.id` 6, interval 1) after one idle beat next to him.
  * With both snake lines alive, a trident hit, a trident hit through
    `BloodDrum` and a `Bomb3` all logged `damage_dealt(amount=0
    target=KingCongaAngry)`, `survived=true`. A `Crate2` also took 0 from
    the trident, so 0 is not special to bosses. In a later attempt the
    player killed every snake first (one hit each, `damage_dealt(amount=2)`)
    and then one trident hit killed him (`damage_dealt(amount=2)`,
    `killed`), which won the run. Not isolated: whether the live lines were
    what made him immune, since the earlier 0-damage tests were also done
    next to the throne.
  * `KingCongaAngry` walks straight down column 0, one tile per beat: in a
    tracked replay he was at (0,-16) after beat 1 and (0,-9) after beat 8,
    and killed a player left standing at (0,-8) (3 damage) around beat
    9 to 11. The snake heads walk down at x = -3 and 3, one tile every 2
    beats, then converge; they reach the player's row after about 20 beats.
  * `SpellEarth` (`spell1`) raised `EarthWall` on the 8 tiles around the
    player at (0,-8). The walls held for 30+ beats: the King stopped at
    (0,-10), and the snake heads stopped at (-2,-8) and (2,-8). Pressing
    toward a wall with the shovel destroyed it (`EarthWall>Floor`), after
    which the next snake head stepped adjacent and could be killed, one hit
    each, from inside the box. With one wall opened per side, both lines
    were cleared with no damage taken; the King then stepped into the
    opening dug on his side and died to one hit.
  * Stepping away from the throne made him step onto the tile next to the
    player; after the 0-damage hit he went back to the throne, and a bomb
    placed at the throne made him jump to (6,-15). He killed the player
    (3 damage) on the 3rd beat the player spent next to him.
  * The bomb test ended with the player dead: of its two `down` presses, only one
    moved (it was left 1 tile from the bomb), and the blast did 4 damage.
  * A `Bat2` that stepped into the trident's line was killed from 2 tiles
    away.
* A shop on 1-3 sold `Food4` for 65 gold (`priceTagCostCurrency.cost`). Its
  walls were `ShopWall` (`digResistance` 4) and `StoneWall`, which the basic
  shovel cannot dig; the shop was not entered.

## Items found

Observed on CotN 4.2.1 as Cadence, no-beat mode.

* Bumping a `ChestBlack` opens it (`killed target=ChestBlack`). Two chests
  gave `Sync_WeaponOnyxDagger` (picked up and swapped in for `WeaponDagger`,
  whose entity then vanished) and `ArmorLeather` (dropped on the chest's tile,
  picked up by walking onto it). Two chests are too few to say what the pool
  is.
* `Sync_WeaponOnyxDagger` has `weapon.damage` 1 like the dagger and the same
  reach, plus a combo: `Sync_itemCombo.combo` goes to 1 after a hit
  (`Sync_itemComboLimit` 1) and the next hit does 1000
  (`Sync_weaponComboDamageMultiplier` base 1, factor 999). Any action that is
  not a hit resets it to 0. Tested against a `Minotaur` (3 health) from one
  snapshot: `right right` hit for 1 then killed; `right idle right` and
  `right idle idle right` hit for 1 both times; `right left right` ended with
  combo 0. A kill also sets it to 1, so the next target dies to its first
  hit: a `Skeleton` kill was followed by a one-hit `Bat`. So any enemy with
  more than 1 health costs two consecutive hits, not its health in hits.
* With `ArmorLeather` a `Minotaur` hit for 3 (`innateAttack.damage` is 4, and
  it did 4 before the armor); not tested on other enemies.
* A `Bomb` pickup (`Bomb`, `Bomb3`) adds to the inventory; the starting
  `Bomb` is spent when placed.
* Standing on a `LockedStairs` tile while its miniboss dies unlocks it and
  descends at once, with no further input.
* More chest loot (run 2, 1-2 and 1-3): `ChestBlack` gave `FeetGlassSlippers`,
  `Sync_ShieldObsidian` ("Multiplier hit protection"),
  `Sync_WeaponTitaniumTrident` and `WeaponTitaniumBroadsword`; `ChestRed`
  gave `FamiliarIceSpirit` and `BloodDrum`; `ChestPurple` gave `SpellEarth`
  ("Raise walls", `spell1`, not cast yet). `FeetGlassSlippers` ("Ignore
  terrain, breakable") left the inventory after the player took damage.
* `Sync_WeaponTitaniumTrident` (`weapon.damage` 2) hits up to 2 tiles in the
  facing direction: it killed a `Bat` 2 tiles away and a `Skeleton2` in one
  hit. It did nothing against a `Ghost` 1 or 2 tiles ahead while the player
  already faced it; the ghost died when it stepped adjacent and the player
  turned to it, as with the dagger.
* `FamiliarIceSpirit` is an action item ("Freeze enemies"): `item1` then a
  direction spawns a `FollowerSnowbro` on that tile. It follows the player and
  freezes what it touches for about 2 turns (`freezable.remainingTurns`), but
  see the `Dragon` note in [zone-one-enemies.md](zone-one-enemies.md) for how
  it blocks melee.
* `BloodDrum` is an action item ("Takes health, increases damage"): `item1`
  cost 1 health (`damage_taken source=BloodDrum`) and set
  `itemConditionalDamageIncrease` to +999 for 1 turn. Not yet tried against
  an enemy.
* Chests and items that a 1-3 level shows: a shop at (-9..-7,1) sold
  `Sync_WeaponOnyxBroadsword` (`itemPrice` 50), `MiscHeartContainer2` (200) and
  `TorchInfernal`; the player had 41 gold and did not buy. A
  `Sync_ShrineOfFeast` had `activeDrop` `FoodMagicCarrot`, `CharmGluttony` and
  `CharmFrost`, and `inactiveDrop` `Food2`; not triggered yet.
* `WeaponTitaniumBroadsword` (`weapon.damage` 2, a 3-tile `multiHit` pattern)
  hits the enemies in the facing line: one swing killed a `Skeleton2` and
  hit a `Skeleton3` behind it, and one hit a `Bat` and a `Minotaur2` (2
  damage each). It killed a `Ghost`, `Zombie`, `Slime3` and `Wraith` in one hit each, but an
  enemy 2 tiles away was not hit by a lone press: the player moved instead.
* `BloodDrum` then a broadsword swing (`item1`, then a direction) killed a
  `Minotaur2` that had 3 of 5 health left and a `Skeleton2` behind it, each
  taking 1001 damage, for 1 health: the 1-3 stairs room guard on one run, at
  2 health left. The swing came the beat after the drum, with the minotaur
  adjacent and not yet having attacked.
* `Sync_ShrineOfFeast` stayed `shrine.active` false and a bump from the left and
  from below only gave `multiplier_lost(because=a failed action)`. What
  activates it is unknown.
* `Crate2` slides one tile away when the player walks into it, and a weapon
  hit on it did `damage_dealt(amount=0)`, so a crate is not broken by melee;
  a bomb breaks crates (see [zone-one-enemies.md](zone-one-enemies.md)). The
  `bomb` input with none left is `multiplier_lost(because=an invalid
  action)`.
* `agent-bridge route` walked the player onto a `SpikeTrap` for 4 damage (12 to
  3 over the run); it ignores traps, so route in short chunks and check the
  map for `SpikeTrap`, `BounceTrap*` and `TempoUpTrap`.

## Shrines

A `ShrineOfBlood` stood in the middle of a 1-1 room (solid, `shrine.name`
"blood", hint "Give blood, get blood weapon"). One `down` into it cost 10
health (`damage_taken(amount=10 source=ShrineOfBlood)`, 12 to 1 in a single
action), and the inventory then held `Sync_WeaponBloodTrident` instead of
`WeaponDagger`, with a `ShovelBlood` listed on the tile below the shrine (it may be a
drop; not checked). The dagger entity stayed at the player's tile. The shrine
stayed in place with `interactable.active` still true, and was not tried a
second time. `agent-bridge route` plans straight
through it (see `live-game-control.md`).

## Unverified

* Whether real-time rhythm behaves differently from no-beat mode.
* Whether a non-moving input is always a dig, and whether a better shovel
  breaks `StoneWall`.
* What `ChestWhite`, the shop and most traps do when engaged. A `SpikeTrap` and a
  `Sync_AutoSpikeTrap` each killed a `Slime3` that walked onto them.
* What `AddchestBlack`, `AddchestRed`, `AddchestWhite`, `CoinsX15` and
  `CoinsX2` do in the starting kit.

Kills leave a coin on the tile that the player collects by walking onto it;
see the gold section of [zone-one-enemies.md](zone-one-enemies.md).

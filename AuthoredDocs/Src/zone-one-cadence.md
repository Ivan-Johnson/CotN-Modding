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
* The `map` command prints `stairs at` for the exit. On 1-1 a `Minotaur` stood
  on it and woke up on its own; once it was dead the stairs worked. On 1-2
  the tile was `LockedStairs` under a `BatMiniboss`: killing the miniboss
  turned it into `Stairs` in the same action. On 1-3 the stairs sat in a
  walled room with a `Minotaur2`, a `Skeleton3`, two `Monkey2`, a `Ghost`,
  two `Bat` and others; it was not entered.
* A `Trapdoor` on 1-3 (at (-1, 9), plain floor to `tile`) took the player to
  1-4 without touching the stairs. `Trapdoor` entities were also listed on 1-1
  and 1-2 (not stepped on), so it may be a way past a locked or guarded exit.
* 1-4 is the boss level: a closed start room of 5 by 5 tiles at the bottom, with
  a `Minotaur2`, `Skeleton3`, `Bat2` and `Ghost` inside, and above it the boss
  room with `Fortissimole`, 14 `Skeleton`s in two rows, four `Ghost`s and
  five `PreBossBarrier` entities across the entrance at y = -7. Nothing there
  was fought.
* A shop on 1-3 sold `Food4` for 65 gold (`priceTagCostCurrency.cost`). Its
  walls were `ShopWall` (`digResistance` 4) and `StoneWall`, which the basic
  shovel cannot dig; the shop was not entered.

## Unverified

* Whether real-time rhythm behaves differently from no-beat mode.
* Whether a non-moving input is always a dig, and whether a better shovel
  breaks `StoneWall`.
* What chests, the shop and most traps do when engaged. A `SpikeTrap` and a
  `Sync_AutoSpikeTrap` each killed a `Slime3` that walked onto them.
* What `AddchestBlack`, `AddchestRed`, `AddchestWhite`, `CoinsX15` and
  `CoinsX2` do in the starting kit.

Kills leave a coin on the tile that the player collects by walking onto it;
see the gold section of [zone-one-enemies.md](zone-one-enemies.md).

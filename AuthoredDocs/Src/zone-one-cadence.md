# Single-zone zone one as Cadence

What a first exploration with `agent-bridge` found on CotN 4.2.1 (see
`live-game-control.md` for the bridge itself). Everything below was observed
live unless it is under "Unverified". Gathered with `agent-bridge new-run
Cadence`, then `state`, `entities`, `spawn`, `input` and `step`.

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

Read from `innateAttack`, `health` and `beatDelay`:

| Type     | Health | `innateAttack.damage` | `beatDelay.interval` |
| -------- | ------ | --------------------- | -------------------- |
| Slime    | 1      | 100                   | 1                    |
| Slime2   | 2      | 2                     | 2                    |
| Skeleton | 1      | 1                     | 2                    |
| Zombie   | 1      | 2                     | 2                    |
| Monkey   | 1      | 0                     | 1                    |
| BatMiniboss | 2   | 3                     | 2                    |

* `Slime2` showed `maxHealth` 4 in one early run; every later measurement
  gave 2.
* Full per-type stats and movement are in [zone-one-enemies.md](zone-one-enemies.md).
* `Slime`'s damage of 100 is as read; I never let one hit me, so I do not know
  what it does in play.
* Dagger kills take one hit per health point: a spawned `Slime2` went from 2 to
  1 to dead over two `right` inputs.

## Behavior

* Enemies in the starting level mostly stayed put while I idled because most
  types do not seek the player (see
  [zone-one-enemies.md](zone-one-enemies.md#movement-ai)). A spawned `Skeleton` or `Zombie` next to the player
  attacked at once.
* A spawned `Skeleton` placed at (3, 0) was adjacent (1, 0) after the one beat
  the spawn took. A spawned `Monkey` moved onto the player's tile. A spawned
  `Slime2` at (3, 0) did not move in three beats.
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

The first run used real-time rhythm, and one `step 1` sample cost 3 to 4 times
`innateAttack.damage`: `Zombie` (`damage` 2) took 12, 6, 0 and `Skeleton`
(`damage` 1) took 12, 8, 5, 1. Several beats passed between commands at about
1 s latency. `new-run` now uses no-beat mode (#18), and the same setup behaves:
a spawned `Skeleton` (`damage` 1, `interval` 2) took the player from 12 to 11,
11, 10, 10, 9, 9 over six `step 1` samples, i.e. its stated damage every second
step. A spawned `Zombie` beside the player did not attack in six steps; it
walks a straight line, and attacks only when the player is on its line.

In no-beat mode the song never ends, a beat cannot be missed, and enemies do
not come to you: time passes only when you act.

## Unverified

* Whether real-time rhythm, which the bridge no longer uses, behaves differently.
* Whether a non-moving input is always a dig, and whether a better shovel
  breaks `StoneWall`.
* What chests, the shop, traps and the `BatMiniboss` do when engaged.
* What `AddchestBlack`, `AddchestRed`, `AddchestWhite`, `CoinsX15` and
  `CoinsX2` do in the starting kit.
* Whether gold from a kill is collected automatically.
* Why enemies idle, such as an aggro range.

## What would help next

The `tile` command (#23) now reads walls and floor. An ASCII map view (#24)
would make it easier still.

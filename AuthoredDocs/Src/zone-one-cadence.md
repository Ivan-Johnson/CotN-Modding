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

Walls and floor are not entities, so `entities` cannot show the map.

## Enemy stats

Read from `innateAttack`, `health` and `beatDelay`:

| Type     | Health | `innateAttack.damage` | `beatDelay.interval` |
| -------- | ------ | --------------------- | -------------------- |
| Slime    | 1      | 100                   | 1                    |
| Slime2   | 2 or 4 | 2                     | 2                    |
| Skeleton | 1      | 1                     | 2                    |
| Zombie   | 1      | 2                     | 2                    |
| Monkey   | 1      | 0                     | 1                    |
| BatMiniboss | 2   | 3                     | 2                    |

* `Slime2` showed `maxHealth` 4 in one run and 2 in every later one. I do not
  know why.
* `Slime`'s damage of 100 is as read; I never let one hit me, so I do not know
  what it does in play.
* Dagger kills take one hit per health point: a spawned `Slime2` went from 2 to
  1 to dead over two `right` inputs.

## Behavior

* Enemies in the starting level mostly stayed put while I idled; they did not
  converge on the player. A spawned `Skeleton` or `Zombie` next to the player
  attacked at once.
* A spawned `Skeleton` placed at (3, 0) was adjacent (1, 0) after the one beat
  the spawn took. A spawned `Monkey` moved onto the player's tile. A spawned
  `Slime2` at (3, 0) did not move in three beats.
* Moving into a wall sometimes did nothing and sometimes moved after a repeat:
  `right` three times from (-1, -3) landed on (0, -3) and then (1, -3) on
  alternate inputs, which fits digging dirt with `ShovelBasic` but is not
  confirmed. Repeated `up` from (1, -3) never moved; I assume a wall the basic
  shovel cannot dig.
* An input takes effect within about one second, as the `state` that follows it
  already shows the result.
* `turnID` rose by about 30 per second even with no input, so it is not a beat
  counter.

## Damage taken looks too high

Standing still next to a spawned enemy and sending one `step 1` per sample
cost the player:

* `Zombie` (`damage` 2): 12, 6, 0.
* `Skeleton` (`damage` 1): 12, 8, 5, 1, then 0, in separate samples a loss of 3
  to 4 per step.

That is about three times the `innateAttack.damage` each time. I do not know
whether one `step` runs several turns, or whether health is scaled. Treat
combat outcomes from `agent-bridge` as unreliable until this is explained. A
spawned enemy beside a 12-health player can kill it within four steps.

## Unverified

* What a `step` really advances, and why damage is about triple.
* Digging, and what stops `ShovelBasic`.
* What chests, the shop, traps and the `BatMiniboss` do when engaged.
* What `AddchestBlack`, `AddchestRed`, `AddchestWhite`, `CoinsX15` and
  `CoinsX2` do in the starting kit.
* Whether gold from a kill is collected automatically.
* Why enemies idle, such as an aggro range.

## What would help next

A bridge command that reads a tile (walls, floor, stairs) would turn this
from probing into mapping.

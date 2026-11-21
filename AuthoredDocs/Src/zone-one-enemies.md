# Zone one enemies

How each enemy that the zone one pool can spawn behaves, measured live with
AgentBridge as Cadence (12 health, dagger, no-beat mode). For the level
layout and the run's starting state see [zone-one-cadence.md](./zone-one-cadence.md).

## Method

* Approach test: start a fresh run, `spawn` the type at (2,0) with the player
  idle at (0,0), then idle 12 beats and record each beat's `entitiesMoved` and
  damage events.
* Attack test: spawn the type at (1,0), then move `right` three times.
* Components came from `entities id=N show=all`. The `activationRange`,
  `beatDelay`, `innateAttack` and `ai` components were read there.

Every beat count below is one player action, not a wall-clock beat.

## Shared components

* All thirteen types below have `activationRange.radius` 3, an `ai.directions`
  list and `aiBasicSeek`.
* `beatDelay.interval` is how many beats pass between the enemy's actions.
* `innateAttack.damage` is the damage of its attack.
* Enemies far from the player also move each beat. With the player idle,
  `Zombie` and `Slime2` ids more than 8 tiles away still stepped every action,
  so `activationRange` is not a limit on movement.

## Stats and behavior

| Type | Health | Interval | Damage | Hits to kill |
|------|--------|----------|--------|--------------|
| `Slime` | 1 | 1 | 100 | 1 |
| `Slime2` | 2 | 2 | 2 | 2 |
| `Slime3` | 1 | 1 | 1 | 1 |
| `Skeleton` | 1 | 2 | 1 | 1 |
| `Skeleton2` | 2 | 2 | 3 | 2 |
| `Skeleton3` | 3 | 2 | 4 | 2 observed |
| `Zombie` | 1 | 2 | 2 | 1 |
| `Monkey` | 1 | 1 | 0 | 1 |
| `Monkey2` | 2 | n/a | 0 | 2 |
| `Bat` | 1 | 2 | 1 | 1 |
| `Bat2` | 1 | 1 | 2 | 1 |
| `Bat3` | 1 | 1 | 3 | 1 |
| `BatMiniboss` | 2 | 2 | 3 | 1 observed |
| `Ghost` | 1 | 1 | 2 | unknown |
| `Wraith` | 1 | 1 | 1 | unknown |
| `Trapchest` | 1 | 1 | 2 | 1 (after a trap) |

"n/a" means the component was not dumped. Damage above is the
`innateAttack.damage`. Observed damage matched it for `Skeleton` (1),
`Zombie` (2), `Skeleton2` (3), `Bat3` (3) and `Ghost` (2). `Skeleton3` dealt
4, so its component was not read.

### Slimes

* `Slime`: never moved in 12 beats and dies in one hit. Its damage of 100 was
  never observed, because nothing attacked.
* `Slime2`: moves every other beat, bouncing between two adjacent tiles. It
  does not approach. It took two hits to kill, and its first hit moved it
  1,1 while adjacent.
* `Slime3`: moves every beat around a 4-tile loop,
  (2,1), (1,1), (1,0), (2,0). Its `aiPattern` moves are `[1,7,5,3]`.

### Skeletons

* `Skeleton`: steps adjacent on the first beat, then hits every second
  beat. Five hits took the player from 12 to 7.
* `Skeleton2`: hits for 3 every two beats. It killed the player in 12 beats
  (12, 9, 6, 3, 0). After one dagger hit it becomes a
  `Skeleton2Headless` and keeps advancing.
* `Skeleton3`: hits for 4 every two beats. It killed the player at 12, 8, 4,
  0. Two dagger hits were needed, and the second moved it next to the
  player.

### Zombie

* Steps adjacent on beat 1, then hits for 2 every second beat.

### Monkeys

* `Monkey` and `Monkey2`: step adjacent on beat 1, then onto the player's
  tile on beat 2 and stay there. They dealt no damage in 12 beats.
* A monkey on the player's tile has grabbed the player. Every move the player
  made (right, left, up) was blocked: the position stayed (0,0) and the dagger
  hit the monkey instead. The components include `grabParalyzeVictim`,
  `grabMoveOntoVictim` and `grabIncreaseHealth` (max 4).
* A grabbing `Monkey` took four hits (`survived=true` three times, then
  `killed`), not one. An ungrabbing `Monkey` dies to one hit; `Monkey2` took
  two.
* Nothing was stolen: the inventory, including both coin stacks, was identical
  after the kill.

### Bats

* Bats fly erratically (`aiMoveOnFallbackCollision` is present), so they
  keep leaving the tile next to the player.
* `Bat2` and `Bat3` move every beat. `Bat3` hit once for 3 within 12 beats.
  `Bat` and `Bat2` never hit within 12 beats.
* `Bat3` has eight directions in its `ai.directions`.
* `BatMiniboss` moves every second beat and did not attack in 12 beats.
  A dagger hit did not kill it.

### Ghost, Wraith, Trapchest

* `Ghost` starts with `aggro.active` false and woke by itself with the player
  3 tiles away. Once awake, it moved only on beats where the player moved away
  from it: it advanced as the player moved left or down and stayed put when
  the player moved toward it. It reached the player's tile and hit for 2.
  That is why it "never moved" in the idle test.
* `Wraith`: `aggro.active` stayed false in every test, including adjacent to
  the player for 6 beats. It has `voiceAggro` (`wraithCry`) and never moved or
  attacked. The player walked onto its tile without hitting it, so a spawned
  `Wraith` seems inert. The earlier "not hit at (1,0)" result is separate:
  (0,3) is a dirt wall, and a `Wraith` spawned there sits inside it.
* `Trapchest` never moved. Moving into it on the second hit dealt 2 damage to
  the player (a trap), and the third hit killed it.

## Unverified

* What wakes a `Wraith`, and whether a spawned one differs from a natural one.
* Why `Slime` never moves. `aggro.active` is true, so it seems to be simply
  stationary, yet its `innateAttack.damage` is 100.
* Whether `BatMiniboss` attacks when adjacent.
* Whether any of these drop gold or change the multiplier when killed.

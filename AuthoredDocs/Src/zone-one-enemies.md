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
| `Skeleton2` | 2 | n/a | 3 | 2 |
| `Skeleton3` | 3 | n/a | 4 | 2 observed |
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
`Zombie` (2), `Skeleton2` (3) and `Bat3` (3). `Skeleton3` dealt 4, so its
component was not read.

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
* A `Monkey` dies to one hit. `Monkey2` took two.
* The components include `grabHopInPlaceOnHit`. I did not check whether a
  monkey steals anything.

### Bats

* Bats fly erratically (`aiMoveOnFallbackCollision` is present), so they
  keep leaving the tile next to the player.
* `Bat2` and `Bat3` move every beat. `Bat3` hit once for 3 within 12 beats.
  `Bat` and `Bat2` never hit within 12 beats.
* `Bat3` has eight directions in its `ai.directions`.
* `BatMiniboss` moves every second beat and did not attack in 12 beats.
  A dagger hit did not kill it.

### Ghost, Wraith, Trapchest

* `Ghost` and `Wraith` never moved in 12 beats and were not hit by the dagger
  at (1,0). The `Wraith` was moved through, so the attack test probably
  spawned it elsewhere. I do not know why.
* `Trapchest` never moved. Moving into it on the second hit dealt 2 damage to
  the player (a trap), and the third hit killed it.

## Unverified

* Why `Slime`, `Ghost` and `Wraith` never move. `aggro.active` was false for
  a `Ghost`, which suggests they wake only in some condition I did not
  trigger.
* What a `Monkey` does while standing on the player's tile.
* Whether `Slime` ever hits for 100.
* Whether `BatMiniboss` attacks when adjacent.
* Whether any of these drop gold or change the multiplier when killed.
* Whether `Skeleton2` and `Skeleton3` have `beatDelay` of 2 like `Skeleton`.
  Their observed hits were two beats apart.

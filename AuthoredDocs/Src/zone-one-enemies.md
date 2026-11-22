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

A second pass re-measured every type in a 5 by 5 open room, spawning with
`spawn TYPE X Y force`, one enemy at a time. Where it contradicts the first
pass, this page now states the second pass. Pitfalls when repeating it:

* The level is random. Check with `tile` that the spawn tile is open; `force`
  places an enemy inside a wall without complaint, and it then just sits.
* Send at most about 20 idles per `input`. Cadence over longer batches
  looked shifted by one beat; single-action calls did not show that. The
  cause is not known.
* A spawned enemy's first action can come one beat late, so beat 1 is not
  always a move.

## Movement AI

`ai.id` picks the movement style, and `ai.directions` holds direction codes:
1 is right, 3 up, 5 left, 7 down, and 2, 4, 6 and 8 are the diagonals.

| `ai.id` | Style | Types |
|---------|-------|-------|
| 0 | stationary | `Slime`, `Trapchest`, the `Headless` skeletons |
| 1 | straight line, reverses at an obstacle | `Zombie` |
| 2 | fixed loop (`aiPattern.moves`) | `Slime2`, `Slime3` |
| 3 | random walk | `Bat`, `Bat2`, `Bat3`, `BatMiniboss` |
| 7 | seeks the player | `Skeleton`, `Skeleton2`, `Skeleton3`, `Monkey`, `Monkey2`, `Ghost`, `Wraith` |

`Wraith` has `ai.id` 7 but never acts; see below.

## Shared components

* All types below have `activationRange.radius` 3, an `ai.directions` list
  and `aiBasicSeek`, whatever their `ai.id`.
* `beatDelay.interval` is how many beats pass between the enemy's actions:
  1 acts every beat, 2 every second beat.
* `innateAttack.damage` is the damage of its attack.
* `aggro.active` is not what makes an enemy act. `Skeleton` and `Monkey`
  start with it false and chase at once.
* Enemies far from the player also move each beat. With the player idle,
  `Zombie` and `Slime2` ids more than 8 tiles away still stepped every action,
  so `activationRange` is not a limit on movement. This was not re-measured.
* Every seeker moves along x first and only then along y, even when the
  vertical distance is larger.
* An attack costs the attacker's slot: once adjacent, `Skeleton`, `Zombie`
  and `Slime2` hit every second beat, and so does `Slime3` (see below).

## Stats and behavior

| Type | Health | Interval | Damage | Hits to kill |
|------|--------|----------|--------|--------------|
| `Slime` | 1 | 1 | 100 | 1 |
| `Slime2` | 2 | 2 | 2 | 2 |
| `Slime3` | 1 | 1 | 1 | 1 |
| `Skeleton` | 1 | 2 | 1 | 1 |
| `Skeleton2` | 2 | 2 | 3 | 2 |
| `Skeleton3` | 3 | 2 | 4 | 3 |
| `Zombie` | 1 | 2 | 2 | 1 |
| `Monkey` | 1 | 1 | 0 | 1, or 4 while grabbing |
| `Monkey2` | 2 | 1 | 0 | 2, or 6 while grabbing |
| `Bat` | 1 | 2 | 1 | 1 |
| `Bat2` | 1 | 1 | 2 | 1 |
| `Bat3` | 1 | 1 | 3 | 1 |
| `BatMiniboss` | 2 | 2 | 3 | at least 2 |
| `Ghost` | 1 | 1 | 2 | 1, only on the turn that faces it |
| `Wraith` | 1 | 1 | 1 | cannot be hit |
| `Trapchest` | 1 | 1 | 2 | 3 bumps |

Damage is the `innateAttack.damage`. Observed damage matched it for
`Slime2` (2), `Slime3` (1), `Skeleton` (1), `Skeleton2` (3), `Skeleton3` (4),
`Zombie` (2), `Bat` (1), `Bat2` (2), `Bat3` (3) and `Ghost` (2).

### Slimes

* `Slime`: stationary and harmless. It did not move or attack in 8 beats,
  even adjacent to the player, so its damage of 100 never fired. One hit
  kills it.
* `Slime2`: bounces down and up (codes `[7,3]`) on every second beat,
  regardless of where the player is. Which direction it starts with depends on
  the spawn tile. If the player is in its path it attacks for 2 every second
  beat and does not move. A move into a wall is skipped and it goes the
  other way instead (spawned at (0,2) with a wall below, it went up first).
* `Slime3`: walks a 4-tile loop on every beat: right, down, left, up
  (`[1,7,5,3]`), so clockwise on screen. The starting corner depends on
  the spawn tile: from (1,1) it goes right first, from (2,2) next to a wall it
  went left first. If the player is on its next step it attacks for 1 every
  second beat, not every beat, and stays put.
* After a hit, `Slime2` carries on with its bounce; the first hit moved it
  from (1,0) to (1,1), which is its normal move, not knockback.

### Skeletons

* `Skeleton`, `Skeleton2`, `Skeleton3`: seek the player, one tile every second
  beat, x first and then y. Next to the player they attack every second
  beat. Which beat they first move on depends on the spawn timing.
* `Skeleton2` and `Skeleton3` hit for 3 and 4, so each kills a 12 health
  player in four and three hits.
* A dagger hit turns `Skeleton2` (first hit) and `Skeleton3` (second hit)
  into `Skeleton2Headless` and `Skeleton3Headless`, shoved one tile away along
  the hit direction. `Skeleton2` needs 2 hits in total and `Skeleton3` needs 3.
  The first hit on `Skeleton3` changed nothing visible.
* A headless skeleton stood still in every test: 7 to 12 beats, with the
  player idle, then moving around the room. Spawned directly it also does
  nothing. It has `charge` components but no `ai` movement (`ai.id` 0). The
  first pass's "keeps advancing" was not reproduced.

### Zombie

* Walks in a straight line, one tile every second beat. The initial direction
  is random (sampled over four directions from the same tile), not toward the
  player. At a wall it pauses one move slot and turns round, so a corridor of
  n tiles gives n-1 moves, a pause, and n-1 moves back.
* It does not chase: it walked past a player standing one tile off its line.
* If the player is next on its line it stops and attacks for 2 every second
  beat. A zombie spawned at (0,-2) did this.

### Monkeys

* `Monkey` and `Monkey2`: seek the player one tile every beat, x first, and step
  onto the player's tile. From (2,0) they were adjacent after beat 1 and on
  the player after beat 2. They deal no damage.
* A monkey on the player's tile has grabbed the player. Every move the player
  made was blocked and the dagger hit the monkey instead. The components
  include `grabParalyzeVictim`, `grabMoveOntoVictim` and `grabIncreaseHealth`.
* Grabbing multiplies the monkey's health: `Monkey` goes from 1 to 4
  (`multiplier` 4, `max` 4) and `Monkey2` from 2 to 6 (`multiplier` 3, `max` 6).
  A grabbing `Monkey` took 4 hits and a grabbing `Monkey2` took 6. A monkey
  hit before it grabs dies to its normal health: 1 hit, or 2 for `Monkey2`.
  A first hit on `Monkey2` moved it back one tile, and it came back.
* Nothing was stolen: the inventory was identical after each kill. No coin
  was left when a monkey died on the player's tile.

### Bats

* Bats take a random step with no bias towards the player. Over about 330 steps
  across `Bat`, `Bat2`, `Bat3` and `BatMiniboss`, 48 to 51% of the steps
  got closer, which is chance. They attack only when a
  random step lands on the player; the hit takes the slot of a move.
* `Bat`, `BatMiniboss`: one step every second beat, in the four
  directions. `Bat2`: one step every beat, four directions. `Bat3`: one step
  every beat, in all eight directions, so diagonals appear.
* A step into a wall seems to be lost, so a bat sometimes skips a beat. Over 40 beats
  `Bat2` and `Bat3` moved 34 to 39 times.
* `Bat3` hit the player 2 to 4 times in 40 beats; `Bat2` hit 0 to 2 times, and `Bat` 3 times in one trial and never in two.
* `BatMiniboss` did not attack in 40 beats. One dagger hit did not kill it.

### Ghost, Wraith, Trapchest

* `Ghost` reacts to which way the player faces. It moves toward the player,
  one tile a beat, x first, only while the player faces away from it, and
  stands still while the player faces it. Facing away means the ghost is
  behind the player: after the player moved up, a ghost at the lower right
  closed in; after the player moved down with the ghost level to the right, it
  stayed. It also keeps closing in while the player idles, as the facing
  persists.
* An adjacent `Ghost` hits for 2 on a beat when the player faces away. Pressing
  toward a ghost while already facing it did nothing at all in 6 tries: no
  hit, no move. A ghost can be killed on the action that turns the player to
  face it: facing left, then pressing right with the ghost adjacent on the right
  killed it in one hit. It starts with `aggro.active` false, and it has
  `stasisAI` and `freezeAttackableFlags` components, which probably
  implement the freeze.
* `Wraith`: inert and not solid, even though `ai.id` is 7. It never moved or
  attacked in any test, including adjacent to the player for 6 beats while the
  player faced away. The player walks through its tile without hitting it, so
  it cannot be hit. `aggro.active` stayed false. What a natural `Wraith` does
  is unknown.
* `Trapchest` never moves. Bumping it once does nothing, the second bump
  deals 2 to the player, and the third kills it. It leaves a random item
  (`HeadSpikedEars`, `WeaponHarp` and `Torch1` in three tries), not coins.

## Gold and the coin multiplier

Read from the player's `grooveChain` and `goldCounter` components after
kills, in no-beat mode.

* A killed enemy leaves a `ResourceCoinN` entity on its tile. The player
  gets the gold by walking onto it.
* The multiplier starts at 1. `grooveChain` has `killsForInitMultiplier` 1,
  `killsPerMultiplier` 4 and `maximumMultiplier` 3, and `killCount` followed
  that: the first kill gave multiplier 2 and the fifth gave 3.
* Six `Slime` kills in a row gave +2, +3, +3, +3, +3, +4 gold. That fits
  "the multiplier at the kill, plus 1", with the multiplier before the
  kill's own increase.
* The chain breaks (`multiplier_lost`, `killCount` back to 0) on an `idle`
  action, even in no-beat mode, and on a failed action such as moving into a
  wall. Moving to an empty tile does not break it.
* Damage taken did not get tested cleanly: the wall bump broke the chain
  before the `Skeleton` hit.
* One kill each, with the coin picked up, gave 2 gold (`Zombie`, `Monkey`)
  and 4 gold (`Skeleton`, `Bat`). Pickups were not confirmed individually,
  so treat those as rough. A `Skeleton2` kill left a `ResourceCoin6`.
* `ResourceDiamond` entities in the entity list are part of the level, not
  drops.

* A third pass measured gold per kill with a fresh run (chain at x1, no
  kills), one enemy spawned at (1,0) in a cleared arena, killed with the
  dagger and its coin walked onto. The gold was the same on every repeat
  (Bat3 three times, Slime and Bat twice):

  | Type | Gold at x1 |
  |------|-----------|
  | `Slime`, `Zombie` | 2 |
  | `Slime3`, `Skeleton`, `Bat` | 4 |
  | `Skeleton2`, `Bat2` | 6 |
  | `Skeleton3` | 8 |
  | `Bat3` | 40 |

  Read together with the six-slime run, a fit is gold = base x (multiplier
  at the kill + 1), with a base of 1 for `Slime` and `Zombie`, 2 for
  `Slime3`, `Skeleton` and `Bat`, 3 for `Skeleton2` and `Bat2`, 4 for
  `Skeleton3` and 20 for `Bat3`. Only `Slime` was seen at a higher
  multiplier, so the formula is a guess for the other types. `Trapchest`
  leaves an item, and `Slime2`, `Monkey2`, `Ghost` and `Wraith` were not
  measured. The earlier "30" for `Bat3` was a higher multiplier, not a
  random value.

## Unverified and still to do

Not yet re-measured in the second pass:

* Whether taking damage breaks the multiplier, and the coin value of
  `Slime2`, `Monkey2`, `Ghost` and the `Bat3` formula at multiplier 2 and 3.
  A test killing three `Bat3` in a row broke the chain between kills, which
  is not explained.
* `Ghost` movement from diagonal positions, and whether it uses the same x
  first rule when blocked.
* How seekers path around obstacles. Every seeker test had a clear line.
* The `activationRange` claim above, and whether an enemy beyond radius 3
  waits. A test at the edge of the room was invalid because `force` had
  spawned the enemy inside a wall.
* Seekers while the player runs away: whether `Monkey` keeps pace and
  `Skeleton` lags.
* Whether a `Zombie` can be hit while walking, and how it reacts to another
  enemy in its way.
* What decides a pattern slime's starting step. `Slime2` and `Slime3` start at
  an index that is the same for the same tile but differs between tiles.
* Whether a bat's lost beats come from walls or something else, and the
  one-beat shift seen on 40-beat batches.
* After some trial sequences, newly spawned enemies stood still, including
  `Slime2` and `Slime3` on open floor, until `new-run`. It followed a blocked
  slime trial once and did not repeat in a clean run, so it may be a
  harness artifact. Not diagnosed.
* What wakes a `Wraith`, and what a natural one does.
* Whether `BatMiniboss` ever attacks, and how many hits kill it.
* Why `Slime` never moves despite `innateAttack.damage` 100.
* `Skeleton2Headless` and `Skeleton3Headless` when a natural level spawns
  them, and what the `charge` components do.
* Everything above was measured as Cadence with a dagger, in no-beat mode.

# Coin multiplier and gold

For players. How kills turn into gold: the chain that raises the multiplier,
what ends the chain, and what each enemy pays. Basic controls:
[controls.md](./controls.md).

## The chain

* The chain starts at x1. The first kill makes it x2 and the fifth kill makes
  it x3, the highest it goes.
* A kill pays at the multiplier you had before it; its own rise applies to the
  next kill.
* Any kill by you extends the chain, bombs included. A bomb that kills several
  enemies counts each one, and pays them in turn at the multiplier the earlier
  kills left: three `Slime`s in one blast pay 1, 2 and 2 gold and leave x2.
* Enemies killed by a floor trap pay nothing and do not extend the chain.
* A `Monkey` that has grabbed you drops nothing and does not extend the chain
  when it dies. One killed before it grabs pays normally.

### What ends the chain

Back to x1 with no kills counted, on:

* an `idle` action;
* a failed move: bumping a wall the shovel cannot dig (`StoneWall`, the level
  edge);
* an invalid action, such as `bomb` with none left;
* taking damage from an enemy's hit, a spike trap or a bomb's blast, your own
  bomb included;
* falling through a `Trapdoor`.

These leave the chain alone: walking onto empty floor, digging a `DirtWall`,
opening a door, placing a bomb, picking up a pile of gold or an item, a
bounce trap, and the health that the Blood Drum costs
([action-items.md](./action-items.md)).

## Gold per kill

Gold = base gold × coin multiplier, with halves rounded up. The coin
multiplier is the chain multiplier plus 0.5 for each coin item held:

* `CoinsX15` ("Coin Multiplier +0.5") adds 0.5.
* `CoinsX2` ("Coin Multiplier +1") also adds only 0.5.
* A Ring of Gold (`RingGold`) adds 1 gold per kill after the multiplication.

With both coin items the chain's x1 pays like x2 and its x3 like x4.
Cadence's single-zone start kit has both ([cadence.md](./cadence.md)); the
table is the pay with neither.

| Type | Base gold |
|------|-----------|
| `Slime`, `Zombie`, `Monkey` | 1 |
| `Slime2`, `Slime3`, `Skeleton`, `Bat`, `Ghost` | 2 |
| `Skeleton2`, `Bat2`, `Monkey2` | 3 |
| `Skeleton3` | 4 |
| `BatMiniboss`, `Minotaur`, `Dragon` | 10 |
| `Minotaur2` | 15 |
| `Bat3`, `Dragon2` | 20 |

An enemy that comes with the level pays the same as one spawned by hand.
A `Trapchest` leaves an item instead ([trapchest.md](./trapchest.md)).

## Picking gold up

A killed enemy leaves one pile; walk onto it to take the gold. A pile gives
its full amount however it looks, and the multiplier does not change it. A small hoard (`ResourceHoardGoldSmall`) holds 25 gold and a large
one (`ResourceHoardGold`) 50. Diamonds give no gold. A bomb's blast destroys
the piles lying in it ([bombs.md](./bombs.md)).

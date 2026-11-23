# Bombs

For players. How bombs are used and what their blast does. The bomb button:
[controls.md](./controls.md).

## Using bombs

* You start with one bomb. A `Bomb` pickup adds one and a `Bomb3` adds three.
* The bomb action drops a lit bomb on your own tile and uses one up. It does
  not block the tile: you can step back onto it, and you can drop another bomb
  on top of it.
* With no bomb left, pressing the button still passes the beat and breaks your
  coin multiplier.
* A bomb goes off on the third beat after the one you placed it on: placed on
  beat 1, it explodes on beat 4. Any action that passes a beat counts,
  including idling.

## The blast

* It covers the 3 by 3 around the bomb, diagonals included, and nothing
  farther. Walls do not shield the corners.
* It goes off before enemies move on that beat, so a charger has to be within
  one tile of the bomb already. A `Minotaur` that starts 4 tiles away when you
  place the bomb and charges is caught; from 5 it steps in just too late. A
  `Dragon`, which moves every second beat, is caught from 3 tiles and missed
  from 4.
* A lit bomb inside another's blast is not set off by it and burns down on its
  own fuse.

## What it hurts

* Everything with health in the blast takes 4: enemies, the shopkeeper and
  you. A `Minotaur` (3 health) or `Dragon` (4) dies to one bomb. A frozen
  `Ghost` is the exception; see [ghost.md](./ghost.md).
* You are safe from 2 tiles away, and hurt from 1 tile, diagonals included.
* Armor reduces it like any hit: leather armor to 3, chainmail to 2, platemail
  to 1.
* You cannot be hurt on two beats in a row, so blasts on consecutive beats hurt
  you once. Blasts two beats apart hurt twice.
* Enemies it kills count towards the coin multiplier and leave their gold
  where they died; the blast does not destroy it. See
  [coin-multiplier.md](./coin-multiplier.md).
* `Crate` and `Crate2` break. A `Crate3` has 3 health and loses 1 per bomb.

## What it destroys

* Dirt walls, stone walls, shop walls, catacomb walls and doors become floor.
  The level border and unbreakable walls stay. For the shovel see
  [digging.md](./digging.md).
* Everything lying on the floor in the blast: coins, diamonds, keys, food,
  weapons, armor, other bombs and a shop's wares. Chests are untouched.
* Traps in the blast: spike, bounce, tempo traps and trapdoors.

## In a shop

* A bomb that destroys wares but misses the shopkeeper is harmless.
* A bomb that hurts the shopkeeper makes him leave his counter, chase you, and
  hit for 20 every second beat. See [shops.md](./shops.md).

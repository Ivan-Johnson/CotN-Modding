# Weapons

For players. How facing, pressing and bumping work: [controls.md](./controls.md).

## How attacks work

* Pressing a direction attacks instead of moving when an enemy stands in one
  of your weapon's trigger tiles; otherwise you move. Every pattern below
  rotates with the direction you press, and "ahead" means that direction.
* A weapon hits an enemy for its full damage. Melee never damages a crate; the
  swing pushes it one tile. A bomb breaks crates ([bombs.md](./bombs.md)).
* Walking onto a weapon lying on the floor equips it and drops the one you
  held on that tile. Stepping onto the tile again swaps them back.
* You can throw a dagger, a spear or a trident with the throw command followed
  by a direction. It flies until it hits a wall, hitting every enemy on the
  way, and lands there; you have no weapon until you pick it up. A trident
  flies three tiles wide. No other weapon can be thrown.

## Families

| Family | Attacks when an enemy is | What it hits |
|--------|--------------------------|--------------|
| Dagger | ahead | the enemy ahead |
| Broadsword | ahead or diagonally ahead | every enemy in those three tiles |
| Longsword | one or two tiles ahead | every enemy in those two tiles |
| Spear | one or two tiles ahead | the nearest enemy in those two tiles |
| Staff | ahead, adjacent | every enemy in the line ahead, to any distance, until a wall |
| Rapier | ahead; or two ahead with nothing adjacent | the enemy ahead; against one two ahead it steps forward and hits for double damage |
| Axe | ahead; or two tiles ahead, or diagonally two ahead | the enemy ahead only; otherwise it steps forward and hits every enemy in the three tiles two ahead |
| Cat | ahead, or beside the tile it steps to | see below |
| Whip | in any of five tiles ahead | one enemy, see below |
| Flail | ahead, diagonally ahead, or beside you | every enemy in those five tiles, each pushed one tile ahead |
| Harp | ahead | then every enemy in the eight tiles around you |
| Trident | ahead; or in the three tiles two ahead | the enemy ahead only; with none, every enemy in the three tiles two ahead |

* **Cat:** an enemy ahead is hit and you stay put. Otherwise you step forward and
  hit one enemy beside the tile you stepped to, the left side before the right,
  then one beside the tile you left, again left first. If there is nothing to
  hit you just move.
* **Whip:** it hits one enemy, the first of these: the tile ahead, the
  diagonals ahead, then the tiles two to each side of the tile ahead. On each
  side pair, the left one goes first.
* **Flail:** an enemy that cannot be pushed, because of a wall or another
  enemy, is still hit.
* **Walls:** a wall directly ahead stops the Longsword, Spear, Rapier, Axe and
  Trident from reaching past it, and a wall further along stops the Staff's line.
  The Broadsword, Whip and Cat still hit enemies beside a wall ahead.

## Materials

Every family comes in basic, Titanium, Obsidian, Golden, Blood, Glass and Onyx
versions; a material changes damage and adds a rule, never the pattern. The
Dagger also comes as Frost, Electric, Phasing and Jeweled, and the Trident as
Titanium, Obsidian, Golden, Blood and Glass. You start with the basic Dagger.

| Material | Damage | Rule |
|----------|--------|------|
| basic | 1 | |
| Titanium | 2 | |
| Jeweled (Dagger) | 5 | |
| Glass | 4 | Shatters the first time you take damage. A Glass Shard, a 1-damage dagger, drops on your tile, and you have no weapon until you step onto it. |
| Obsidian | your coin multiplier | Hits for 1, 2 or 3 as the multiplier rises ([coin-multiplier.md](./coin-multiplier.md)). |
| Golden | 1 | The action right after you pick up gold hits for 999 more. Picking up a diamond does not count, and an action in between loses it. Kills also drop more gold. |
| Blood | 1 | At 1 health, half a heart, it hits for 999 more. Every tenth kill heals 1 health. |
| Onyx | 1 | After a hit, every hit in an unbroken run deals 1000 more, across targets and directions. An idle or a move ends the run; a kill counts as a hit. |
| Frost (Dagger) | 1 | A hit freezes the enemy for the next three actions, and hitting a frozen enemy kills it. |
| Electric (Dagger) | 2 | Every enemy touching the one you hit, diagonals included, and so on along a chain, takes 1. |
| Phasing (Dagger) | 2 | Hits what other weapons cannot: an enemy inside a wall, and a ghost you are facing ([ghost.md](./ghost.md)). It does not reach past a wall. |

A Rapier lunge doubles the damage of any material.

## Later zones

Zone one chests and shops hold no bows, crossbows, cutlasses, warhammers,
rifles, blunderbusses or Onyx Tridents. The Blunderbuss fires one shot for 2
damage at every enemy in a cone, one tile wide ahead, three tiles wide two
ahead and five tiles wide three ahead, and knocks you back one tile.
Afterwards it only hits the tile ahead, for 2.

Where weapons were found: [chests-and-loot.md](./chests-and-loot.md).

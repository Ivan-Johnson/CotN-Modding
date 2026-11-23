# Digging

For players. Walking into a wall (see [controls.md](./controls.md)) digs it when
your shovel is strong enough. The wall turns to floor and you stay where you
are; the next move steps into the gap, so getting through takes two actions.
A wall that is too tough for your shovel does not give way, and the failed
move breaks your coin multiplier. A successful dig keeps it
([coin-multiplier.md](./coin-multiplier.md)).

## Walls

| Wall | Toughness | Notes |
|------|-----------|-------|
| Dirt wall (`DirtWall`) | 1 | Some hold a pile of 25 gold (`DirtWallWithGold`) or a diamond (`DirtWallWithDiamonds`) that lands on the dug tile. |
| Stone wall (`StoneWall`) | 2 | |
| Catacomb wall (`CatacombWall`) | 3 | |
| Shop wall (`ShopWall`) | 4 | Leaves 10 gold on the dug tile. |
| Earth wall (`EarthWall`, from `SpellEarth`) and doors | none | Any move opens them, shovel or not. |
| Level border and locked doors | no shovel digs them | |

* A wall torch is removed with its wall. A wall spike (`Sync_WallSpike`) set in
  the wall hurts you for 1 when you dig it out.
* Bombs clear stone walls too: [bombs.md](./bombs.md).

## Shovels

A shovel digs every wall up to its strength.

| Shovel | Strength | Also |
|--------|----------|------|
| Shovel (`ShovelBasic`), Glass Shard (`ShovelShard`) | 1 | |
| Shovel of Courage (`ShovelCourage`) | 1 | Digging a dirt wall carries you into the gap in the same action. |
| Titanium Shovel (`ShovelTitanium`) | 2 | |
| Battle Shovel (`ShovelBattle`) | 2 | The attack on the action right after a dig kills the enemy however much health it has. A pause in between cancels it. |
| Shovel of Strength (`ShovelStrength`) | 2 | Also digs every wall touching the one you hit that it could dig on its own. |
| Crystal Shovel (`ShovelCrystal`) | 3 | |
| Glass Shovel (`ShovelGlass`) | 3 | Digs one shop wall, then shatters. With no shovel you can dig nothing but earth walls and doors. |
| Pickaxe (`Pickaxe`) | 3 | Takes one hit per point of toughness: one on dirt, two on stone, three on catacomb. |
| Blood Shovel (`ShovelBlood`) | 1 | Digs any wall that can be dug, for 1 health per wall tougher than dirt. |
| Obsidian Shovel (`ShovelObsidian`) | your coin multiplier | Dirt at x1, stone at x2, catacomb at x3. The multiplier caps at 3, so never a shop wall. |

## Enemies that dig

* A `Minotaur` or `Minotaur2` digs through dirt walls, stone walls, earth walls
  and doors, but not catacomb or shop walls. The dig takes the beat it would
  have moved, so it stands still for one beat at the wall.
* A `Dragon` digs through dirt, stone, catacomb and shop walls, but not the
  level border.

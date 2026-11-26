# Shrines

For players. A shrine is a solid block in a level that makes you one deal.
Most shrines are used by walking into them: you stay on your tile, the deal
happens at once, and walking in again does nothing. Four shrines ignore a
bump and are set off by something you do beside them instead. The shrine's
hint is the line of text shown above it.

## The shrines

A level can hold any of these fifteen in an all-zones run, and any but the
Shrine of Rhythm in a single-zone run. Two more shrines appear only in
multiplayer games.

| Shrine | Hint | Walking into it |
|--------|------|-----------------|
| Shrine of Blood (`ShrineOfBlood`) | Give blood, get blood weapon | Drops you to 1 health, however much you had. Your weapon becomes a random blood weapon, and the old one is left on your tile. A Blood Shovel appears on the tile below the shrine. |
| Boss Shrine (`ShrineOfBoss`) | Gain items, extra miniboss | A row of three items to choose from. |
| Shrine of Chance (`ShrineOfChance`) | Win items, if you're lucky | Costs 10 gold, and the price doubles with each use (10, 20, 40, ...). It never runs out. Some uses drop an item near it and others give nothing. With less gold than the price, nothing happens. |
| Shrine of Darkness (`ShrineOfDarkness`) | Turns out the lights | Gives a Map, a Compass and a Ring of Shadows. Your torch and your old ring are destroyed, not dropped. |
| Shrine of Glass (`ShrineOfGlass`) | All items become glass | Your weapon, shovel, armor, headgear, boots and torch become their glass versions (a dagger becomes a Glass Dagger). Rings, charms, spells and holy water stay as they are. |
| Shrine of Peace (`ShrineOfPeace`) | Lose items, gain health | One more heart container, and full health. Despite the hint, it takes none of your items. |
| Shrine of Rhythm (`ShrineOfRhythm`) | Items become obsidian, irregular rhythm | Your weapon, shovel and armor become their obsidian versions (a dagger becomes an Obsidian Dagger). Your ring stays. |
| Shrine of Risk (`ShrineOfRisk`) | Gain items, slowly lose health | Puts a Bag of Holding and two apples (`Food1`) in your inventory, and a row of three items to choose from. |
| Shrine of Space (`ShrineOfSpace`) | Gain shovel, bigger levels | A row of three shovels to choose from. |
| Shrine of Uncertainty (`ShrineOfUncertainty`) | Get mystery weapon | Your weapon becomes a random "uncertain" weapon, and the old one is left on your tile. |
| Shrine of War (`ShrineOfWar`) | Gain items, tougher enemies | Puts two items straight into your inventory. |
| Shrine of Pain (`ShrineOfPain`) | Take hits near me | Nothing. See [Pain](#pain). |
| Shrine of Sacrifice (`ShrineOfSacrifice`) | Requires sacrifices | Nothing. See [Sacrifice](#sacrifice). |
| Shrine of the Feast (`Sync_ShrineOfFeast`) | Overeat near me | Nothing. See [Feast](#feast). |
| Shrine of Fire (`Sync_ShrineOfFire`) | Hit me with fire | Nothing. See [Fire](#fire). |

The rewards are random: two shrines of the same kind give different items.
What the blood, glass and obsidian weapons do: [weapons.md](./weapons.md#materials).
The Blood, Glass and Obsidian Shovels: [digging.md](./digging.md#shovels).

## A row of three

Several shrines put their reward in a row of three items on the tiles just
below them. Take one and the other two vanish. Taking an item for a slot you
have filled, such as a shovel from the Shrine of Space, leaves your old one on
that tile.

## Shrines set off beside them

### Pain

Each hit you take while standing on a tile beside the shrine (left, right,
above or below, not diagonal) drops one item on a tile next to you. It pays
out for five hits, however much each hit does, and every item is yours to
take.

### Sacrifice

Kill five enemies on the tiles beside it (left, right, above or below) and it
puts out a row of three. A kill on a diagonal or two tiles away does not
count.

### Feast

Eat food at full health while standing right beside it, and one item appears
on the tile below it. Eating while hurt, or from three tiles away, does
nothing.

### Fire

A fireball or a bomb blast that reaches it sets it off, and it puts out a row
of three.

## Bombs

A bomb blast destroys a shrine. Each leaves one item where it stood, except
the Shrine of Fire, which leaves its own tile empty and puts one item on each
of the three tiles below it. The Shrine of Blood leaves a Crown of Thorns if
unused and a Ring of Regeneration if used. What else a blast destroys: [bombs.md](./bombs.md#what-it-destroys).

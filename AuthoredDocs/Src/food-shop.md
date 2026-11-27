# Food shop

For players. The secret shop that sells food and a heart container, and its
shopkeeper, who answers a bomb with bombs. Applies to Cadence in Single Zone
mode. Finding the shop, its cracked wall and the travel rune that takes you
there and back: [secret-shops.md](./secret-shops.md).

## The room

* A closed room of 7 by 9 tiles, walled with shop wall. The Food Shopkeeper
  (`Shopkeeper4`) stands near the back, and the travel rune back to the
  level is 4 tiles in front of him.
* Two wares, priced in gold, lie two tiles in front of him: food one tile to
  his left, and a heart container one tile to his right.

## The wares

The food is one of the six ordinary foods, never magic food, and the heart
container is one of four kinds. Each costs its usual price:

| Food | Price |
|------|-------|
| Apple (`Food1`) | 10 |
| Carrot (`FoodCarrot`) | 20 |
| Cheese (`Food2`) | 25 |
| Drumstick (`Food3`) | 40 |
| Cookies (`FoodCookies`) | 50 |
| Ham (`Food4`) | 65 |

| Heart container | Price | Max health | Health |
|-----------------|-------|------------|--------|
| Empty Heart Container (`MiscHeartContainerEmpty`) | 25 | +1 heart | +0 |
| Heart Container (`MiscHeartContainer`) | 50 | +1 heart | +1 heart |
| Empty Double Heart Container (`MiscHeartContainerEmpty2`) | 100 | +2 hearts | +0 |
| Double Heart Container (`MiscHeartContainer2`) | 200 | +2 hearts | +2 hearts |

* Buying works as in the regular shop ([shops.md](./shops.md#buying)): walk
  onto a ware with at least its price in gold. With less, the move fails and
  you keep your gold.
* Food goes into your inventory, to eat with the item button
  ([controls.md](./controls.md)). A heart container takes effect at once.

## The Food Shopkeeper

* Until something hurts him, your weapon cannot: attacking him does nothing,
  and he never attacks you or leaves his tile. A bomb whose blast misses him
  leaves him alone.
* He has 1 health, so a bomb that catches him kills him. He then:
  * drops the Gluttony Charm (`CharmGluttony`) where he stood;
  * leaves both wares free to take;
  * throws one or two lit bombs onto or beside you. Each goes off one or two
    beats later with a bomb's blast ([bombs.md](./bombs.md)), taking 4 if you
    are still within one tile. A step on the next beat that leaves you two
    tiles from a bomb beside you dodges it.

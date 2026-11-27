# Pawnbroker

For players. The secret room where the `Pawnbroker` buys your items for
gold, then offers his own wares. Applies to Cadence on the first floor of
each zone. Finding the room, its cracked wall and its travel rune:
[secret-shops.md](./secret-shops.md).

## The room

* Its travel rune hides in a cracked catacomb wall (`CatacombWallCracked`).
* The room is 5 tiles wide, walled in shop wall. The Pawnbroker stands at
  the top of its middle column, and the travel rune is 6 tiles below him.
  His label asks "Sell one of your items?".
* Two rows below him is a 3x3 block of tiles, each naming one item slot.
  Its middle tile cannot be entered:

  |        |          |        |
  |--------|----------|--------|
  | head   | shield   | ring   |
  | body   | *blocked*| shovel |
  | feet   | torch    | weapon |

## Selling

* Step onto a slot's tile to sell the item in that slot. You land on the
  tile, the item is gone for good, and he pays half its shop price, rounded
  down: a Torch2 (15) brings 7, a Longsword (50) 25. The price is the same
  in every zone.
* He refuses items worth nothing to him: the starting Dagger and Shovel, and
  items with no shop price such as Sonar. A refused or empty slot's step
  fails: you stay where you are, keep the item, and get nothing.
* He buys 24 items per room. After that, stepping onto a slot tile sells
  nothing.

## His wares

* Your second sale opens his shop: three wares, priced in gold, appear on
  the row where the travel rune stood, and the rune moves two tiles down. Buy
  one by walking onto it, as in a regular shop ([shops.md](./shops.md)).
* Each further sale swaps the three wares for new ones.
* Buy one ware and the other two vanish, and your next sale brings no new
  ones.
* From your seventh sale, the shop holds a single special offer instead,
  and the next sale changes it. It costs all your gold but 1, so buying it
  leaves you 1 gold.
* No refunds: an item bought from him does not sell back to him.

## Angering him

* Your weapon cannot hurt him: attacking him does nothing, and he never
  attacks you.
* A bomb that hurts him provokes him. He has 6 health and a bomb takes 4.
  Bombs: [bombs.md](./bombs.md).
* Provoked, the slot tiles vanish, so selling is over. He chases you and hits
  for 20, more than Cadence's full health of 12
  ([cadence.md](./cadence.md)). Your weapon now hurts him: a dagger takes 1
  per hit.
* Killed, he drops a coupon (`MiscCoupon`) and a pile of gold.

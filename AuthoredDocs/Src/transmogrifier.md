# Transmogrifier

For players. The secret room where the `Transmogrifier` swaps one of your
items for a random new one of the same kind, for gold. Applies to Cadence on
the first floor of each zone. Finding the room, its cracked wall and its
travel rune: [secret-shops.md](./secret-shops.md).

## The room

* Its travel rune hides in a cracked stone wall (`StoneWallCracked`).
* Inside is a floor 5 tiles wide and 8 tall, walled in shop wall. The
  Transmogrifier stands on the middle column, 3 rows from the top, and the
  rune you arrive by is 3 tiles below him.
* The eight tiles around him each name one item slot:

  |        |          |        |
  |--------|----------|--------|
  | head   | shield   | ring   |
  | body   | *him*    | shovel |
  | feet   | torch    | weapon |

* His label asks "Transmogrify one of your items?" and shows the current
  price.

## Transmogrifying

* Step onto a slot's tile to transmogrify the item in that slot. You pay the
  price, the item is gone, and you land back on the rune. A new, different
  item for the same slot lies free on the tile between the rune and his
  torch tile; walk onto it to take it.
* The new item is never the starting Dagger or Shovel.
* The first use costs 10 gold, in every zone. Each use doubles the price
  (10, 20, 40, ...), whichever tile you used, and he never runs out.
* Having exactly the price is enough. One gold short, the step onto the tile
  fails: you stay where you are and keep your gold and your item.
* With nothing in that slot, the step fails too, and costs nothing. Cadence
  starts with only a weapon and a shovel, so only those two tiles work until
  she picks up more.
* He takes any item Cadence can carry in those eight slots.

## The Transmogrifier

* His tiles keep you two tiles from him, and neither a spear's reach nor a
  bomb set off below his tiles hurts or provokes him. How the regular
  shopkeeper reacts to attacks: [shops.md](./shops.md#the-shopkeeper).

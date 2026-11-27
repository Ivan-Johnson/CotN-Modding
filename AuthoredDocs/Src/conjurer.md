# Conjurer

For players. The Conjurer's secret room, where gold buys a new random item
for the slot you choose. Applies to Cadence on the first floor of a
single-zone run. Finding the room and travelling to and from it:
[secret-shops.md](./secret-shops.md).

## The room

* A shop-walled room five tiles wide and eight deep, enclosed by the level
  border, which nothing digs or bombs ([digging.md](./digging.md)), so the
  travel rune is the only way in or out. The rune is in the middle column,
  second row from the bottom. The Conjurer (`Conjurer`) stands in the top
  row, second column from the left.
* Below him is a 3-by-3 grid of eight floor tiles, one per item slot, with a
  blocked centre:

  |        | Left | Middle    | Right  |
  |--------|------|-----------|--------|
  | Top    | head | shield    | ring   |
  | Middle | body | (blocked) | shovel |
  | Bottom | feet | torch     | weapon |

  The torch tile is two tiles above the rune.

## Conjuring

* Step onto a slot's tile to buy a random new item for that slot. The first
  purchase costs 40 gold, and the price doubles after every purchase, on any
  tile: 40, 80, 160, 320 and so on.
* The item does not replace anything. It lands, free, on the floor just above
  the rune, and the item you already hold in that slot stays yours. The slot
  can be empty.
* The purchase moves you onto the rune. Standing there does not send you out
  of the room; stepping off and back onto it does.
* With less gold than the price, the step fails: you stay where you are and
  keep your gold.

## The Conjurer

* Your weapon cannot hurt him: attacking him does nothing, and he never
  attacks you.
* A bomb kills him; he has 1 health. Bombs: [bombs.md](./bombs.md). Once he
  is dead the tiles do nothing: stepping on one costs no gold and gives no
  item.

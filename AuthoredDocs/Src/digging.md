# Digging

For players. What the player can dig through, measured as Cadence in no-beat
mode on CotN 4.2.1. Walls and floor are tiles; a mod author's view is in
[synchrony-game-control.md](./synchrony-game-control.md).

| Wall | Dig resistance | Basic shovel (`ShovelBasic`) |
|------|----------------|------------------------------|
| `DirtWall` | 1 | digs |
| `StoneWall` | 2 | did not give way in 3 tries |
| `ShopWall` | 4 | not dug (`guess`, from the number; the shop was not entered) |
| `LevelBorder` | none | solid; the outer edge of the level |

* Moving into a `DirtWall` leaves the player in place and turns the tile into
  `Floor`; the next move walks through. A dug wall takes two actions.
* A door (`DoorVertical`, `DoorHorizontal`) opens the same way, without a dig,
  in two actions.
* A bomb clears `StoneWall` too; see [bombs.md](./bombs.md).
* `SpellEarth` raises `EarthWall`, which the shovel destroys
  (`EarthWall>Floor`); see [action-items.md](./action-items.md).
* `StoneWall` with a better shovel is untested.

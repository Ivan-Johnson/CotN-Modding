# Secret shops

For players. The secret rooms hidden behind cracked walls: which wall hides
which room, how the travel rune takes you in and back, and how often each room
appears. What each room offers is on its own page. Applies to Cadence unless a
bullet names another character.

## Cracked walls

* A secret room's entrance is a cracked wall: a dirt, stone or catacomb wall
  drawn differently from the plain one. A level has a cracked wall only when
  it has a secret room, and then exactly one.
* A cracked wall is as tough as the plain wall of its kind, so it takes the
  same shovel ([digging.md](./digging.md)): the starting shovel opens only a
  cracked dirt wall. A bomb opens any of them, and the rune under it still
  works ([bombs.md](./bombs.md)).
* The kind of wall tells you which rooms can be behind it:

| Cracked wall | Toughness | Room behind it |
|--------------|-----------|----------------|
| Cracked dirt wall (`DirtWallCracked`) | 1 | Arena, Conjurer or Shriner |
| Cracked stone wall (`StoneWallCracked`) | 2 | Transmogrifier, Blood shop or Glass shop |
| Cracked catacomb wall (`CatacombWallCracked`) | 3 | [Food shop](./food-shop.md) or Pawnbroker |

## The travel rune

* Under the cracked wall lies a travel rune. Dig the wall, step onto the
  rune, and a moment later you stand on the matching rune inside the secret
  room.
* The room is a closed patch of floor walled with shop wall, and digging
  through that wall reaches only the level border, so the room's rune is the
  only way out. Stepping onto it puts you back on the tile where the cracked
  wall stood.
* Standing on a rune after arriving does not send you back: step off and on
  again. Both runes keep working, so you can go back and forth.
* You keep your items and gold. An enemy beside you when you step on stays
  behind.

## Where secret rooms appear

* A level has at most one secret room, and a boss level never has one.
* **Single Zone mode**, in any zone: each of floors 1 to 3 has a secret room
  roughly half the time. A run never has the same room twice, and never has
  the Transmogrifier. Any other room can be on any of the three floors, the
  Blood shop included.
* **All Zones mode:** every run has all eight rooms, each once, on eight
  different regular levels. The Blood shop is always on 1-1 or 1-2.
* In All Zones mode some characters miss some rooms: Aria and Coda never get
  the Blood shop or the Food shop, Dove never gets the Arena, and Monk never
  gets the Pawnbroker.

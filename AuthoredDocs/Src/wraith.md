# Wraith

For players. Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `Wraith` | 1 | 1 | 1 | natural: 1; spawned: cannot be hit |

A `Wraith` behaves differently when spawned by hand than when it comes with a
level.

* **Spawned:** it is inert and not solid. It never moved or attacked in any
  test, including adjacent to the player for 6 beats while the player faced
  away. The player walks through its tile without hitting it.
* **Natural:** a `Wraith` in a 1-2 skeleton room walked toward the player one
  tile a beat and died to one dagger hit. Another, on 1-3, went from (3,4) to
  (-2,0) in one beat with the player at (-2,5), then walked down 1 tile a beat
  and died to one hit. Why it jumped is unknown.
* So the spawned one is not how a wraith behaves in a level. What wakes a
  spawned `Wraith`, and what a natural one does besides chase, is unknown.

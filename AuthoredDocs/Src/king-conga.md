# King Conga

For players. One of the bosses that can guard 1-4; which boss you get and the
level's layout: [stairs-and-levels.md](./stairs-and-levels.md).
Stats columns: [enemies.md](./enemies.md#stats-tables).

| Type | Speed | HP | Damage | Hits to kill |
|------|-------|----|--------|--------------|
| `KingConga` (seated) | does not move | 2 | does not attack | cannot be hurt while a zombie lives |
| `KingCongaAngry` (angered) | 1 | 2 | 3 | 2 with the Dagger, once every zombie is dead |
| `ZombieSnakeYellow`, `ZombieSnake` | 2 | 1 | 2 | 1 |

## The room

* King Conga sits on his throne at the top of the room, with two conga lines
  of eight zombies beside it, one on each side. A yellow zombie leads each
  line.
* Nothing in the room moves until you step into it. Stepping in seals the
  entrance behind you with boss walls.

## The conga lines

* Each leader walks toward you one tile every second beat, and the zombies
  behind it follow in its footsteps.
* When a leader dies, the next zombie in its line takes over.

## King Conga

* **Seated.** He stays on his throne as long as you never idle and never fail
  an action. A zombie hitting you does not anger him, and standing next to
  him while he sits is safe.
* **Angered.** An idle angers him, and so does a failed action such as
  bumping a wall ([controls.md](./controls.md#failed-actions)), hitting him
  on his throne, or killing every zombie.
* **Angry**, he comes at you one tile a beat, diagonals included, and hits
  for 3 on the beat after he reaches you and every second beat after that.
* **Shielded.** While any zombie lives, hits do him no damage. Hit him off
  his throne and he jumps back onto it, seated again; hit him on it and he
  gets angry where he sits.
* **Killing him.** Once every zombie is dead, hits hurt him. A hit that does
  not kill him makes him jump to another tile of the room, at least three
  tiles from you. A 2-damage weapon kills him in one hit
  ([weapons.md](./weapons.md#materials)).
* **Reward.** He drops no gold. His death opens a path behind the throne to
  the stairs.

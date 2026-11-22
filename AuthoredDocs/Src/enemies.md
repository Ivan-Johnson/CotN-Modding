# Zone one enemies

For players. Which enemies zone one can spawn and how each one moves. Each
type has its own page; follow the links.

* Slimes: [Slime, Slime2, Slime3](./slimes.md)
* [Skeletons](./skeletons.md): Skeleton, Skeleton2, Skeleton3 and the
  headless variants
* [Zombie](./zombies.md)
* [Monkeys](./monkeys.md): Monkey, Monkey2
* [Bats](./bats.md): Bat, Bat2, Bat3
* [Ghost](./ghost.md) and [Wraith](./wraith.md)
* [Trapchest](./trapchest.md)
* [Minibosses](./minibosses.md): BatMiniboss, Minotaur, Minotaur2, Dragon,
  Dragon2
* [King Conga](./king-conga.md), a 1-4 boss

Stats, damage and drops that cut across types: [coin multiplier](./coin-multiplier.md),
[bombs](./bombs.md), and [digging](./digging.md). For the AI codes mod authors
use, see [enemy-ai-ids.md](./enemy-ai-ids.md).

## How the numbers were measured

Every page states what it measured as Cadence (12 health, dagger) in no-beat
mode on CotN 4.2.1, with the enemy spawned by hand in a cleared open room,
unless it says *natural* (the enemy came with the level). "Beat" means one
player action, not a wall-clock beat; in no-beat mode time passes only when
the player acts.

Each stats table has the same columns:

* **Speed**: 1 acts every beat, 2 acts every second beat.
* **HP**: health points; a dagger hit takes 1.
* **Damage**: health the player loses per hit.

## Shared behaviour

* A seeker moves along x first and only then along y, even when the vertical
  distance is larger.
* An attack takes the attacker's move slot: once adjacent, a speed-2 enemy hits
  every second beat.
* Enemies that were more than 8 tiles away still stepped every action while
  the player idled (seen with `Zombie` and `Slime2`; not re-measured), so
  distance alone does not keep an enemy still.

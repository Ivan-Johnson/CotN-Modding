# Zone one enemies

For players. What all enemies have in common; each type has its own page.

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
[bombs](./bombs.md), and [digging](./digging.md).

## Stats tables

Each page's table has the same columns:

* **Speed**: 1 acts every beat, 2 acts every second beat.
* **HP**: health points; a dagger hit takes 1.
* **Damage**: health you lose per hit.

## When enemies act

* **Always active:** Slime2, Slime3 and Zombie act from the first beat and from
  any distance.
* **Sleepers:** Skeletons, monkeys and bats do nothing until you come within 3
  tiles of them, measured in a straight line: a tile 2 across and 2 up is in
  range, 3 across and 1 up is not. Walls do not matter. Once awake, a skeleton
  chases and a bat wanders however far you go.
* **Minotaurs and Dragons:** a Minotaur wakes within 7 tiles, a Dragon2 within
  10, and walls do not matter for that either. All Minotaurs and Dragons also
  wake once they have a clear line to you, even from across a room. A Dragon has
  no distance of its own and sleeps behind a wall at any distance.
* A [Ghost](./ghost.md) wakes by its own rule.
* The enemies a level starts with follow the same rules: on a fresh level
  only the always-active types move, and the sleepers wait for you to come
  close.
* Awake enemies keep acting while you stand still.

## Timing

* A speed-2 enemy acts on the first beat after it appears and then on every
  second beat. A speed-1 enemy acts every beat.
* An attack takes the place of a move, so a speed-2 enemy next to you hits every
  second beat.
* Nothing can hurt you on the first beat of a level.

## Movement

* Skeletons, monkeys and Minotaurs chase one step at a time, horizontally
  first, even when you are farther away vertically.
* When a wall or another enemy blocks a skeleton's horizontal step it steps
  vertically instead. It never walks around an obstacle: a skeleton with a
  wall or an enemy straight between it and you stays where it is.
* A Minotaur with a wall straight between it and you breaks the stone or dirt
  wall, which costs it one extra beat.
* A Skeleton always makes the same moves from the same starting point. A
  Zombie's first direction and a bat's every step are random.

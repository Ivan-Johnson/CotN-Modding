# Gary the Cowardly Sheep

Vocabulary for the `GaryTheCowardlySheep` mod's game design: a playable
character, **Muriel**, like Mary but whose sheep is a coward. Synchrony API
terms are in `Mods/GLOSSARY.md`.

## Language

**Muriel**:
A selectable playable character, identical to Mary except for her name and
that her sheep is **Gary**. Mary herself is unchanged.
_Avoid_: Gary the Cowardly Sheep (the mod's name), Mary variant

**Gary**:
The sheep that accompanies **Muriel**, in place of Mary's sheep. Always the
sheep, never the character.
_Avoid_: Lamb, pet, familiar

**Hostile enemy**:
An enemy hostile to **Gary** that is not passive, so an unprovoked shopkeeper
or dormant exploding mushroom is not one, and neither is a crate or barrel,
which is no enemy at all.
_Avoid_: Threat, aggressive enemy

**Cower**:
The state **Gary** is in while any **Hostile enemy** is in his **Cower zone**.
It changes nothing about how Gary moves or acts, and does not exist in the
vanilla game.
_Avoid_: Scared, afraid, frightened

**Cower zone**:
The tiles within two tiles of **Gary** by taxicab distance, his own included,
regardless of walls: a **Hostile enemy** in it makes him **Cower**.
Highlighted yellow while he does not Cower.
_Avoid_: Danger radius, cower radius

**Facing**:
The direction of **Gary**'s most recent move. He has none until he first
moves.
_Avoid_: Heading, orientation

**Fright zone**:
The 3-wide, 2-deep block of tiles directly behind **Gary**'s **Facing**,
highlighted red while he **Cowers**. Gary has no Fright zone while his
Facing is diagonal or before he has one.
_Avoid_: Behind zone, danger zone

**Death by fright**:
**Gary**'s instant death when **Muriel** or a **Hostile enemy** occupies the
**Fright zone** while he **Cowers**. Its consequence is the same as a vanilla
sheep's death; only the cause is new.
_Avoid_: Scare death

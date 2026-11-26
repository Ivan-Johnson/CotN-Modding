# Gary the Cowardly Sheep

Vocabulary for the `GaryTheCowardlySheep` mod's game design: a playable
character like Mary whose sheep is a coward. Synchrony API terms are in
`Mods/GLOSSARY.md`.

## Language

**Gary the Cowardly Sheep**:
A selectable playable character, identical to Mary except that her sheep is
**Gary**. Mary herself is unchanged.
_Avoid_: Gary mod, Mary variant

**Gary**:
The sheep that accompanies **Gary the Cowardly Sheep**, in place of Mary's
sheep. Always the sheep, never the character.
_Avoid_: Lamb, pet, familiar

**Hostile enemy**:
An enemy hostile to **Gary** that is not passive, so an unprovoked shopkeeper
is not one.
_Avoid_: Threat, aggressive enemy

**Cower**:
The state **Gary** is in while any **Hostile enemy** is within two tiles of him
by taxicab distance, regardless of walls. It changes nothing about how Gary
moves or acts, and does not exist in the vanilla game.
_Avoid_: Scared, afraid, frightened

**Fright zone**:
The 3-wide, 2-deep block of tiles directly behind **Gary**'s cardinal facing,
highlighted red while he **Cowers**. Gary has no Fright zone while facing
diagonally.
_Avoid_: Behind zone, danger zone

**Death by fright**:
**Gary**'s instant death when Mary or a **Hostile enemy** occupies the
**Fright zone** while he **Cowers**. Its consequence is the same as a vanilla
sheep's death; only the cause is new.
_Avoid_: Scare death

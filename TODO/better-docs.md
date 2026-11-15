* Have LLM identify fill in major gaps in the docs. e.g. the docs probably
  assume that the reader already knows stuff such as:

  * Basic character mechanics: equipment slots, how glass gear works, etc
  * How all the different characters work (cadence vs melody vs aria ...)
  * Boss mechanics (esp story mode bosses?)
  * Enemy mechanics (e.g. most enemies are cardinal & every-other beat)

* Core mechanics that the rendered docs do not explain. Find the answer in
  game or by tracer bullet, then add to `Mods/GLOSSARY.md`:

  * Player turn: the order in which a move resolves into attack, dig, or
    interact.
  * The full order of a hit (`objectDealDamage` to `objectTakeDamage` to
    `objectDeath`), and what armor and shields do within it.
  * What each extra mode (seeded, daily, hardcore, no-return, all-zones, story)
    changes. `ExtraMode` lists identifiers only.
  * Shrines, shops and shopkeepers, vaults, and secret rooms as general
    mechanics.
  * Cursed and glass (fragile) items: whether they are a general item flag, and
    which component implements each.
  * What each item slot means for the player (the docs describe capacity and
    HUD only).
  * Groove chain and coin multiplier as players experience them.
  * Whether enemies share a general movement cadence (cardinal, every-other-beat)
    or whether it is per-enemy.

* Make docs more ergonomic. (I'm not really sure what that would look like...
  Partly done: `nix build .#docs` leaves the Markdown at
  `result/docs/markdown/`, which agents search with `grep`/`view`.

* Next steps:

  1. One last pass of ~/Workspaces/4/CotN-Modding/result/docs/markdown/ looking
     for any remaining undiscovered nuggets of wisdom

  2. Mine the game's own data: make a mod that'll dump out all available game
     data. e.g. enemy definitions, character starting items, list of all
     items/gear with metadata (e.g. how much health each type of food heals)

  3. Self discovery. Make a mod that allow AI agents to actually interact with
     a CotN game.

  4. As an absolute last resort, allow agents to de-compile CotN.

     This almost certainly won't be necessary -- anything that can't be
     discovered via in-game tests isn't worth knowing?

  Integrate all discovered info into
  CotN-Modding/result/docs/markdown/unofficial/. e.g
  unofficial/{raw-game-data/items.json,docs/foo.md}

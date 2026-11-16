* Core mechanics that the rendered docs do not explain:

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
  * Basic character mechanics: equipment slots, how glass gear works, etc
  * How all the different characters work (cadence vs melody vs aria ...)
  * Boss mechanics (esp story mode bosses?)
  * Enemy mechanics (e.g. most enemies are cardinal & every-other beat)

* Next steps:

  1. Big picture doc cleanup/reorg. Forget about the fact that most of the docs
     originate from https://vortexbuffer.com/synchrony/docs/index.html instead
     suppose that we had a authoring the docs ourselves as a green-field
     project. How would we want to structure the docs?

	 * Use: /writing-for-agents /itj-writing-for-humans /domain-modeling

	 * Most of Mods/GLOSSARY.md gets migrated to a GLOSSARY.md in the new
       green-field docs

	 * Better file structure & filenames: more directories, with a README.md
       file in each

	 Basically:

	 * man-pages should use the green-field version

	 * produce two versions of markdown:

	   * existing `/markdown/` gets renamed to `/markdown-stream/` or some such.

	   * new `result/docs/markdown/` is the greenfield version containing:

	     * Any new docs (e.g. `Mods/GLOSSARY.md`)

	     * All the good parts of the official docs
           (e.g. `result/docs/markdown/vortexbuffer.com/synchrony/docs.md`) but
           none of the useless / near-useless stuff
           (e.g. `result/docs/markdown/vortexbuffer.com/synchrony/docs/modules/necro.game.item.Currency.md`
           is an API spec; it doesn't belong in the docs)

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

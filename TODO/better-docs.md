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

  1. ~~Scope how much of the official docs are useful~~ Done.

     Very little is useful, judging by this POC: DocDownloader/useful-docs.bash

     ./result/docs/markdown-useful:

     * docs.md - not useful; this is intended for the general playerbase
       (humans who lack programming experience).

       Some bits could be useful, but not much; it isn't worth patching out the
       useful bits. It'd be far easier to just rewrite from scratch.

     * components/* - not useful. This entire directory is just documentation
       for the modding APIs. Some nuggets of info would be useful when writing
       our own docs, but these files aren't useful in and of themselves.

     * overview/{01..05}*.md

       01 is useless.

       02..05 are potentially useful

     result/docs/markdown/vortexbuffer.com/synchrony/docs/{modules,events}:
     similar to markdown-useful/components, but even less reusable.

  1. Mine the game's own data: make a mod that'll dump out all available game
     data. e.g. enemy definitions, character starting items, list of all
     items/gear with metadata (e.g. how much health each type of food heals).

     Status: POC - Mods/ScrapeGameData/ScrapeGameData.lua

     Next steps: `copilot-containerized
     --resume=93bb73dd-399f-4cd4-bd10-a3999178c980`


     ```
     The design tree is empty. I've updated the glossary entries for Mirror and Game data to match the branch decision. Nothing else has been implemented.

     Plan

     1. POC first (Q7): make ScrapeGameData also emit a versions.json with the CotN build and the Synchrony version. First probe which API exposes them. If none does, skip versions and note that in Mods/ScrapeGameData/Docs/sources.md.
     2. Shared helper: DocDownloader/push-to-mirror.bash does the clone, replace-contents, soft-reset commit and push, with MIRROR_REMOTE overridable. crawl-and-push.bash is refactored to use it.
     3. DocDownloader/push-game-data.bash [SCRAPE_DIR]:
     • It defaults to the newest directory under Tmp/scrape-game-data/.
     • It pushes to the game-data branch of CotN-docs, with no BUILD_MODE.
     • It uploads only the four mod-emitted datasets. necrodancer-xml.json and NecroDancer.log are excluded.
     • It adds the same four git/timestamp provenance files as the crawl, plus scrape-dir.txt, plus versions.json if the POC succeeds.
     • It generates README.md from DocDownloader/game-data-README.md on every push, warning of the possible proprietary risk and explaining the separate branch.
     • It refuses to push if a dataset is missing or empty, or if the log contains [ScrapeGameData] ERROR.
     • It is run directly, not as a flake app, and nix flake check never runs it.
     4. Tests: test-push.bash runs against a local bare repo and is wired into nix flake check. It covers the push replacing branch contents, the README being generated, and both guards.
     5. Docs: 0005-game-data-lives-on-its-own-mirror-branch.md, plus short updates to DocDownloader/README.md and AGENTS.md.

     Shall I proceed? I'd start with the POC.
     ```

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

  1. Self discovery. Make a mod that allow AI agents to actually interact with
     a CotN game.

  1. As an absolute last resort, allow agents to de-compile CotN.

     This almost certainly won't be necessary -- anything that can't be
     discovered via in-game tests isn't worth knowing?

  Integrate all discovered info into
  CotN-Modding/result/docs/markdown/unofficial/. e.g
  unofficial/{raw-game-data/items.json,docs/foo.md}

# Documenting many pages at once

For the session coordinating a bulk pass over `AuthoredDocs/Src/`. Each page is
one run of [SKILL.md](./SKILL.md); this file covers running several.

* **Pilot first.** Do one page end to end and show it before fanning out: the
  reader's corrections to the standard are cheapest on one page.
* **One agent per page.** Brief it with the page, its neighbours to link by
  planned name (a page not yet written is fine), and "use the
  `cotn-document-mechanic` skill". It owns its page and its test file.
* **Shared files.** Agents leave the test framework (`Mods/TestFramework/`,
  including `fixtures.lua`) alone unless a helper is truly needed, and say so
  in their return. They report contradictions in other pages to you instead of
  editing them.
* **One game.** Runs queue on the game lock, so experiments from several
  agents interleave. A test run takes seconds, so contention is rare.
* **Worktrees** work: scripts act on the checkout they run in, so each agent
  can commit in its own.
* **Merge serially.** Cherry-pick each agent's commit; cherry-picks skip the
  commit hook, so run the full suite once afterwards (`nix run
  .#itj-impure-tests`). Resolve `Src/README.md` by hand.
* **Then sweep** the dangling links and cross-page contradictions the agents
  reported, in separate commits.

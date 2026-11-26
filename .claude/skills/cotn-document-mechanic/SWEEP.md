# Documenting many pages at once

For the session coordinating a bulk pass over `AuthoredDocs/Src/`. Each page is
one run of [SKILL.md](./SKILL.md); this file covers running several.

* **Hub first.** When the sweep's pages link a hub page, write and land the
  hub before spawning the others, or cherry-pick its commit into each agent's
  worktree as soon as it exists. The docs check fails a link to a missing
  page, so until the hub is in its tree, no page's commit passes its own hook.
* **One agent per page.** Brief it with the page, its neighbours to link by
  planned name, and "use the `cotn-document-mechanic` skill". It owns its page
  and its test file.
* **Shared files.** Agents leave the test framework (`Mods/TestFramework/`,
  including `fixtures.lua`) alone unless a helper is truly needed, and say so
  in their return.
* **One game.** Runs queue on the game lock, so experiments from several
  agents interleave. A test run takes seconds, so contention is rare.
* **Worktrees** work: scripts act on the checkout they run in, so each agent
  can commit in its own.
* **Merge serially.** Cherry-pick each agent's commit; cherry-picks skip the
  commit hook, so run the full suite once afterwards (`nix run
  .#itj-impure-tests`). Resolve `Src/README.md` by hand.
* **Then sweep** the dangling links and cross-page contradictions the agents
  reported, in separate commits.

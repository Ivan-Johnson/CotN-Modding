# Agent instructions

Crypt of the NecroDancer (CotN / cotn) is a rhythm-based roguelike where
movement, combat, and survival happen to the beat. Its Synchrony version adds
full Lua modding support.

## Contexts

This repo has multiple contexts and no `GLOSSARY-MAP.md`; this section is the
map. Each context has its own `AGENTS.md` and `GLOSSARY.md`. Before touching a
context, read both, and use the glossary's terms rather than the ones it lists
under `_Avoid_`.

* `Mods/`: the Synchrony API and game concepts that mods are written against;
  builds the mods themselves.
* `DocDownloader/`: mirrors the official Synchrony docs and renders them.
* `GameData/`: scrapes data out of the live game and publishes it to the docs
  mirror.
* `AuthoredDocs/`: the docs written by hand, and the docs tree that publishes
  them beside the official docs and the game data.

Each context has two audiences. Its **maintainer** is whoever changes the
context itself, human or agent. Its **user** is defined in its `GLOSSARY.md`.

Relationships between contexts:

* **GameData → Mods**: the `ScrapeGameData` mod in `Mods/` is the source of
  the data.
* **GameData → DocDownloader**: GameData publishes to DocDownloader's mirror,
  sharing its push mechanism.
* **DocDownloader → AuthoredDocs**: DocDownloader's converted official docs go
  into the docs tree that AuthoredDocs builds.
* **GameData → AuthoredDocs**: the game data goes into the docs tree too.
* **AuthoredDocs → Mods**: the docs tree is the API reference that the Mods
  glossary is derived from, and the authored docs are guides for writing mods.

ADRs for every context live in `Docs/Adr/`. Read those touching the area you
are about to change. When your output contradicts one, say so explicitly rather
than silently overriding it.

## Commands

* `build-release` runs `nix flake check`, the nix formatting check, and the
  live tests that the changed paths can affect. The `commit-msg` and
  `pre-push` hooks run it. How it picks the live tests, and how to run them
  yourself: `Mods/AGENTS.md`, "Dev loop"; why: ADRs 0008 and 0009.
* A crashed or hung game fails every live run with "game not responding".
  A game that runs but has stopped noticing changes to the bundle fails it
  with "the game did not load the installed mods"; turning `DevBundle` off
  and on in the game's mods menu recovers it. Restarting or toggling the game
  is the user's job; agents cannot reach it from the sandbox.
* Scripts act on the checkout they run in (`git rev-parse --show-toplevel`),
  never on the workspace's `ITJ_FLAKE_ROOT`, so a git worktree installs and
  tests its own mods.
* `build-format` formats all code. The pre-commit hook runs it, so you rarely
  need to.

## Learning about the game

To find out how the game works, write a unit test that observes it, as
`AuthoredDocs/Src/testing.md` describes. When something seems not to happen
in no-beat mode, read its "No-beat mode" section before concluding so. Why: `Docs/Adr/0007-unit-tests-are-the-default-way-to-learn-the-game.md`.

## Conventions

* Flake inputs `follows` nixpkgs, so pin bumps go through `flake.lock` rather
  than per-input nixpkgs versions.
* File & directory names all start with a letter. Where possible, a directory's
  first letter is upper case (A-Z) and a file's is lower case (a-z); the rest of
  the name is unconstrained, so `game-data-README.md` and `Mods/Foo-Bar/` are
  fine. This is not always possible; e.g. `README.md` files and the nix
  `result` symlink.
* Each commit cleans up the docs that relate to its main purpose: update or
  remove any claim it supersedes, in every page that states it. Grep for the
  old wording, for the concept's key terms, and for any _Avoid_ term the
  commit adds to a `GLOSSARY.md`, in `Docs/Adr/` too. If you notice stale
  docs unrelated to the commit, don't fix them there; flag them for the
  user's review.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `Ivan-Johnson/CotN-Modding`, via `gh`. See
`Docs/Agents/issue-tracker.md`.

**Implementing an issue:** end the commit message with `Closes #<n>` (on the
last commit if there are several), one keyword per issue on its own line, so
the push closes it; don't close it by hand.

### Triage labels

Default five-role vocabulary, plus a `priority:now` label. See
`Docs/Agents/triage-labels.md`.

## Tracer bullet first

Documentation and example code for this modding API are sparse. Before
designing a change that leans on an API you haven't used before in this repo (a
new event, a cross-mod mechanism, a manifest field, etc.), fire a tracer bullet:
build a small standalone POC and verify it live (see each context's dev loop). Treat
such a task as two steps, POC then the real change, and finish the POC before
designing the real change.

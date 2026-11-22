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

* `build-release` runs `nix flake check` and the nix formatting check, and
  also runs `nix run .#itj-impure-tests` since this flake provides it.
* The impure tests reload the mods and wipe the live game run, so every
  non-`--no-verify` commit does. During a live run, commit docs-only changes
  with `--no-verify` and re-run the checks at the end.
* `nix run .#itj-impure-tests` installs `HelloWorld` and `HelloWorldTests` via
  `install-mods` (see `Mods/AGENTS.md`), forces `HelloWorldTests` to reload so
  its automated test run
  fires, and prints only the new `NecroDancer.log` lines produced by that run.
  CotN live-reloads unpacked mods, so this is the whole inner dev loop: edit,
  run `nix run .#itj-impure-tests`, read the result. It's an `app`, not a
  `check`, because it's impure: it needs a running, native Steam/Proton CotN
  instance.
* `build-format` formats all code. Typically this does not need to be used; it
  is done automatically as part of a pre-commit hook.

## Conventions

* Flake inputs `follows` nixpkgs, so pin bumps go through `flake.lock` rather
  than per-input nixpkgs versions.
* File & directory names all start with a letter. Where possible, a directory's
  first letter is upper case (A-Z) and a file's is lower case (a-z); the rest of
  the name is unconstrained, so `game-data-README.md` and `Mods/Foo-Bar/` are
  fine. This is not always possible; e.g. `README.md` files and the nix
  `result` symlink.
* Each commit cleans up the docs that relate to its main purpose: update or
  remove any claim it supersedes, in every page that states it (grep for the
  old wording). If you notice stale docs unrelated to the commit, don't fix
  them there; flag them for the user's review.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `Ivan-Johnson/CotN-Modding`, via `gh`. See
`Docs/Agents/issue-tracker.md`.

**Implementing an issue:** end the commit message with `Closes #<n>` (on the
last commit if there are several).

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

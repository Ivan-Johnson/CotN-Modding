# Agent instructions

Crypt of the NecroDancer (CotN / cotn) is a rhythm-based roguelike where
movement, combat, and survival happen to the beat. Its Synchrony version adds
full Lua modding support.

This repo has two halves, each with its own `AGENTS.md` covering the details:

* `DocDownloader/` mirrors the official Synchrony API documentation and renders
  it to Markdown and man pages.
* `Mods/` builds the Synchrony mods themselves, and consumes those rendered
  docs as its API reference.

Read `GLOSSARY-MAP.md` at the start of every task, then the glossary of each
context the task touches. Use their terms, and avoid the ones they list under
`_Avoid_`.

## Commands

* `build-release` runs `nix flake check` and the nix formatting check, and
  also runs `nix run .#itj-impure-tests` since this flake provides it.
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
* Decisions with their reasons live in `Docs/Adr/`; read the relevant one
  before changing the shape it records.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `Ivan-Johnson/CotN-Modding`, via `gh`. See
`Docs/Agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary, plus a `priority:now` label. See
`Docs/Agents/triage-labels.md`.

### Domain docs

Multi-context: `GLOSSARY-MAP.md` at the root, ADRs in `Docs/Adr/`. See
`Docs/Agents/domain.md`.

## Tracer bullet first

Documentation and example code for this modding API are sparse. Before
designing a change that leans on an API you haven't used before in this repo (a
new event, a cross-mod mechanism, a manifest field, etc.), fire a tracer bullet:
build a small standalone POC and verify it live (see each half's dev loop). Treat
such a task as two steps, POC then the real change, and finish the POC before
designing the real change.

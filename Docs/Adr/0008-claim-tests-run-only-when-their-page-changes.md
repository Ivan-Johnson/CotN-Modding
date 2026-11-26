# Claim tests run only when their page changes

Live tests fall into two kinds (see `Mods/GLOSSARY.md`). A code test checks
this repo's code. A claim test backs a claim on one authored doc. With no
gameplay mod installed beside it, a claim test can only start failing when
its page, its own file, the test harness, or the game itself changes. The git
hooks and `build-release` therefore run a claim test only for those changes,
and they run a mod's code tests only when that mod, its tests, or the harness
changes. This cuts the live run, which takes about 90 s and reloads the game,
on most commits and pushes.

## Considered options

* **Run the full suite on every change that touches mod code.** This was the
  old rule. Rejected: most commits paid for claim tests they could not affect.
* **Keep claim tests in `HelloWorld`.** Rejected: `HelloWorld`'s gameplay
  code spawns entities in every level, so a code change could change a
  claim test's result.
* **Install `HelloWorld` during claim runs, and run every claim test when
  its code changes.** Rejected in favour of never installing it with claim
  tests, which keeps a claim test's levels the same in every run.

## Consequences

* Claim tests live in their own mod, `Mods/ClaimTests/`, with no gameplay
  code. Each file backs exactly one page and is named after it:
  `Mods/ClaimTests/weapons.lua` backs `AuthoredDocs/Src/weapons.md`. A flake
  check requires each file to have its page. It does not check the reverse.
* No mod with code tests (originally just `HelloWorld`) is installed while
  claim tests run. A run that needs both kinds does two passes, which costs
  one more game reload.
* A change to the harness (`Mods/TestFramework/`, the runner and install
  scripts in `Mods/LiveGame/`, `Mods/flake-module.nix`, `flake.nix`,
  `flake.lock`) runs every test. A path that no list names also runs every
  test, so that the scope fails safe. The offline tests
  (`Mods/LiveGame/test-*`) are not harness: `nix flake check` runs them, and
  the live suite never reads them.
* A push applies the same rule to each pushed commit. A manual
  `build-release` applies it to the uncommitted changes to tracked files, or
  to the last commit when there are none.
* A game update changes no path in the repo, so it triggers no claim test.
  After an update, force a full run: `nix run .#itj-impure-tests` with no
  arguments.

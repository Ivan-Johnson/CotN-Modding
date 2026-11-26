---
name: cotn-document-mechanic
description: >-
  Document one Crypt of the NecroDancer game mechanic as a player page backed
  by live unit tests. Use when writing, rewriting or fact-checking a page under
  `AuthoredDocs/Src/` about how the game works: an enemy, item, weapon, trap,
  control, or any rule a player relies on.
argument-hint: "<page or mechanic, e.g. traps.md>"
---
# Document a game mechanic

Turn one subject (a page of `AuthoredDocs/Src/`) into verified conclusions
and the tests that keep them true. Invoke `itj-good-prose` first. The page
shape, audiences and conventions are in `AuthoredDocs/AGENTS.md` and
`AuthoredDocs/GLOSSARY.md`; how to write and run a test is in
`AuthoredDocs/Src/testing.md`. Read all three.

Running many pages at once: [SWEEP.md](./SWEEP.md).

## Steps

1. **Question.** Read the page and the pages it links. List what a player
   needs to know about the subject as questions. Done when every claim on the
   page is a question or is cut.
2. **Experiment.** Answer each question with scratch tests that call
   `api.observe`, many trials per question and every relevant case: spawned
   and level-generated enemies, each facing, each blocker. One run settles
   nothing; repeat until the answer does not change. Done when each question
   has a verified answer or is dropped.
3. **Write.** Rewrite the page as conclusions only. Done when each sentence
   states something verified.
4. **Test.** Keep the fewest permanent tests that back each claim, with real
   assertions, in `Mods/ClaimTests/<page>.lua`. Delete the scratch
   tests. Done when `luacheck --config Mods/.luacheckrc Mods` is clean and
   `nix run .#itj-impure-tests` passes in full.
5. **Cross-check.** Grep `AuthoredDocs/Src/` for pages that quote or depend on
   a claim you changed. Fix claims your findings contradict; report the rest
   instead of rewriting other subjects' pages. Done when the grep is clean or
   reported.
6. **Commit** the page and its tests together.

## Return

The conclusions now on the page, the questions you dropped, contradictions
found in other pages, and the commit hash.

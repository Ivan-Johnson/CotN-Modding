# Unit tests are the default way to learn about the game

To answer a question about game mechanics, an agent writes a unit test that
reports the values it wants with `api.observe`, runs it alone with
`nix run .#itj-impure-tests -- <testName>`, and reads the `OBSERVED` lines.
Each run starts from a fixed seed, takes the game-instance lock, and needs no
per-step turns. This replaces `AgentBridge` (see
`0006-agent-bridge-uses-command-file-and-log.md`), which is deleted. The
workflow lives in `AuthoredDocs/Src/testing.md`.

An interactive bridge made every experiment a hand-driven session: about one
command per second, and no record of what had been measured. A test is
repeatable, reviewable, and can stay in the suite as a regression test once
the answer is known.

## Considered options

* **Keep `AgentBridge` as the primary tool.** Rejected: slow, and its
  experiments left nothing behind.
* **Keep it beside unit tests, for questions tests cannot answer.** Rejected
  for now: no such question has come up, and it cost a mod, a CLI and a
  transport to maintain. It can be rebuilt from ADR 0006 and
  `AuthoredDocs/Src/synchrony-game-control.md` if one does.
* **Observe values from unit tests.** Chosen.

## Consequences

* Only one process may drive the game at a time, so `run-tests` takes a lock
  on the game instance first; see the root `AGENTS.md`.
* An experiment that needs interactive steps must script them in the test's
  `onLoad`.
* Game facts found by experiment go in `AuthoredDocs/Src/`, not in agent
  instructions.

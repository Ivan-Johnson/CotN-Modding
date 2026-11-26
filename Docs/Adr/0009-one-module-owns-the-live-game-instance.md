# One module owns the live game instance

There is one running game, and every install replaces the whole bundle mod
(ADR 0004) with `rsync --delete`. Two callers that overlap therefore break
each other: a scrape during a test pass would swap the bundle out from under
the suite. The game-instance lock used to live in the test runner alone, and
the scrape repeated the install, reload and wait sequence by hand with no lock
and no check for a silent game.

Every caller that drives the live game now goes through `live-game-run`
(`Mods/LiveGame/live-game-run.bash`). One call takes the lock, records where
the log ends, installs the named mods, forces a reload, and, given a line to
wait for, checks that the game loaded the install, waits for the line and
prints only the log lines the call added. It fails fast when the game stops
logging. `install-mods` is an internal part of it.

The lock is held for one call, which is one test pass, not for a whole test
run. Each pass reinstalls the whole bundle, so another caller that slips in
between two passes leaves nothing behind that the next pass relies on. A lock
held across the run would need the runner to take it and then tell each pass
that the lock is already held, which widens the interface for no gain in
correctness.

A caller waits for the lock as long as a pass may take: the lock wait
defaults to the default pass timeout, 900 s, whatever timeout the caller sets
for its own wait. It therefore outwaits a whole pass of another caller instead
of failing while that pass is still healthy.

## Considered options

* **Hold the lock for a whole test run.** Rejected: each pass is
  self-contained, and passing an "already locked" flag to every pass widens
  the interface.
* **Keep `install-mods` public beside `live-game-run`.** Rejected: an install
  outside the lock can replace the bundle during another caller's wait.
* **Take the lock inside `install-mods`, with a bypass for the runner.**
  Rejected: the lock must also cover the wait for the log line, and a bypass
  lets a caller skip the lock again.
* **One module that installs, reloads and waits under the lock.** Chosen.

## Consequences

* The flake exposes `live-game-run`, not `install-mods`, as its app and
  dev-shell command, and `liveGame` exports only `live-game-run` to GameData.
* Another caller may use the game between two passes of a test run.
* A caller passes extra bundle files and the reload trigger as options;
  the environment variables `install-mods` reads are internal.

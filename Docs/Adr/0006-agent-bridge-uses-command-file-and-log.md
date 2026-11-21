# The agent bridge speaks a command file in and the game log out

`AgentBridge` lets an AI agent drive a live game. An agent outside the game
writes commands to a file inside the mod's own directory; the mod polls that
file from `event.tick` and executes the commands there. The mod answers with
request-ID-tagged single-line `print()` output in `NecroDancer.log`, which the
agent tails. A flake-app CLI, `agent-bridge`, hides this so the transport can
change without touching agent instructions.

The mod sandbox leaves no better channel. A tracer-bullet POC found that mods
cannot write files, that `io` and `os` are absent, and that `Storage`, `HTTP`,
`DebugDump` and `LocalProxy` are blocked. `IPC` and `ServerSocket` load, but
neither is a generic channel. Reading files works, and so does `print()`.

## Considered options

* **A socket or IPC channel.** Rejected: unavailable to the Lua sandbox.
* **The mod writes a response file.** Rejected: mods cannot write files.
* **Command file in, log out.** Chosen: the only transport that works.

## Consequences

* Latency is about 1 s per command, because the game flushes its log about
  once a second.
* Large responses (entity dumps) are chunked into base64 lines, as
  `ScrapeGameData` does.
* The command file must live inside a mounted mod's directory; a directory
  without a `mod.json` is invisible to `FileIO`. `install-mods` rsyncs with
  `--delete`, so a reinstall removes it.
* Each command runs from the `event.tick` that read it, not in-turn. An
  earlier design queued each one for `event.turn` behind an `IDLE` input, but
  that idle turn dropped the player's groove chain and used up a spawned
  enemy's spawn invincibility. Effects do not survive rollback, which is
  acceptable only because the mod is single-player. See
  `AuthoredDocs/Src/live-game-control.md`.
* `AgentBridge` is dev-only. It logs a warning on load and refuses commands
  outside a single-player session.
* Starting and stopping the game is out of scope; the CLI reports a timeout
  when the mod does not answer.

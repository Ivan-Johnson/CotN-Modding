#!/usr/bin/env bash
# Sends one command to the AgentBridge mod in the running game and prints its
# JSON reply. The mod can only be read from NecroDancer.log, so this writes the
# command file and waits for the reply lines tagged with its ID.
#
# Usage: agent-bridge install
#        agent-bridge COMMAND [ARG...]
#
# Commands (replies are JSON; `input` and `step` pass beats, and `new-run`
# uses no-beat mode, so time passes only when you act):
#   state                           the player's position, health and items
#   entities [type=T] [component=C] [id=N] [show=C1,C2|all]
#                                   entities with a position (or component C);
#                                   `show` adds their components' fields
#   spawn TYPE [X Y]                next to the player by default
#   convert ID TYPE
#   input ACTION                    up, down, left, right, up_left, ..., idle,
#                                   item1, item2, bomb, throw, spell1, spell2
#   step N                          advance N beats
#   new-run [CHARACTER]             start a SingleZone run
#   level N
#
# Environment: COTN_LOG, COTN_LOCAL_MODS_DIR, ITJ_BUNDLE_NAME (default
# DevBundle), ITJ_AGENT_BRIDGE_TIMEOUT (seconds, default 30). Expects
# `wait_for_log` from the flake, and `install-mods` on PATH.
set -euo pipefail

bundleName="${ITJ_BUNDLE_NAME:-DevBundle}"
timeoutSeconds="${ITJ_AGENT_BRIDGE_TIMEOUT:-30}"
modDir="$COTN_LOCAL_MODS_DIR/$bundleName/AgentBridge"

if [[ ${1:-} == "" ]]; then
	sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
	exit 2
fi

if [[ $1 == install ]]; then
	baseline=$(wc -l <"$COTN_LOG")
	ITJ_BUNDLE_RELOAD_TRIGGER="AgentBridge/AgentBridge.lua" install-mods AgentBridge
	if ! wait_for_log "$baseline" "[AgentBridge] ready"; then
		echo "agent-bridge: the mod did not report ready" >&2
		exit 1
	fi
	echo "agent-bridge: ready"
	exit 0
fi

if [[ ! -d $modDir ]]; then
	echo "agent-bridge: AgentBridge is not installed; run 'agent-bridge install'" >&2
	exit 1
fi

id="$(date +%s%N)"
baseline=$(wc -l <"$COTN_LOG")

# Rename, so the mod never reads a half-written file.
printf '%s %s\n' "$id" "$*" >"$modDir/.cmd.tmp"
mv "$modDir/.cmd.tmp" "$modDir/cmd.txt"

deadline=$((SECONDS + timeoutSeconds))
while ((SECONDS < deadline)); do
	replies="$(
		tail -n "+$((baseline + 1))" "$COTN_LOG" |
			grep -aF "[AgentBridge] $id " |
			sed -E 's/^.*\[AgentBridge\] [^ ]+ //; s/"[[:space:]]*$//' || true
	)"
	first="${replies%%$'\n'*}"
	case "$first" in
	ERROR*)
		echo "agent-bridge: ${first#ERROR }" >&2
		exit 1
		;;
	DATA*)
		total="${first#DATA *\/}"
		total="${total%% *}"
		if (($(grep -c '^DATA ' <<<"$replies") >= total)); then
			sed -E 's/^DATA [0-9]+\/[0-9]+ //' <<<"$replies" | tr -d '\n' | base64 -d
			echo
			exit 0
		fi
		;;
	esac
	sleep 0.1
done

echo "agent-bridge: no reply in ${timeoutSeconds}s; is the game running with AgentBridge installed ('agent-bridge install')?" >&2
exit 1

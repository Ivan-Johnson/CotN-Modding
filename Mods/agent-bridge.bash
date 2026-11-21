#!/usr/bin/env bash
# Sends one command to the AgentBridge mod in the running game and prints its
# Sends one command to the AgentBridge mod in the running game and prints its
# reply as compact text. The mod can only be read from NecroDancer.log, so this
# writes the command file and waits for the reply lines tagged with its ID.
#
# Usage: agent-bridge [--json] COMMAND [ARG...]
#
# Any command installs AgentBridge into the bundle first when it is missing.
# `--json` (or ITJ_AGENT_BRIDGE_JSON=1) prints the raw JSON reply instead. In
# the compact form, `input` and `step` print a header (health, position, level,
# turn) and one line per action: `right+(1,0)` moved there, `right=` did not,
# then its events, dug tiles, and the entities within 6 tiles that moved.
#
# Commands (`input` and `step` pass beats, and `new-run`
# uses no-beat mode, so time passes only when you act):
#   state                           the player's position, health, facing, coin
#                                   multiplier, kill count, gold and items
#   entities [type=T] [component=C] [id=N] [show=C1,C2|@preset|all]
#                                   entities with a position (or component C);
#                                   `show` adds their components' fields.
#                                   `@ai` expands to the components that decide
#                                   how an enemy moves and attacks (also usable
#                                   in scenario's `watch=`). Replies are ASCII:
#                                   bytes above 0x7f arrive as \u00XX escapes
#   tile X Y [X2 Y2]                the tile at X Y, or every tile in the
#                                   rectangle (up to 400): its name, whether it
#                                   is solid, a wall or a floor, and the dig
#                                   resistance a shovel must beat
#   spawn TYPE [X Y] [force]        next to the player by default; refuses a solid
#                                   or off-level tile unless `force` is given
#   convert ID TYPE
#   clear [arena=N]                 remove every enemy (anything with an `ai`),
#                                   so spawn tests see only what they spawn;
#                                   arena=N (1 to 10) also turns the square
#                                   within N tiles of the player into floor,
#                                   dropping wall torches and spikes there
#   input ACTION...                 up, down, left, right, up_left, ..., idle,
#                                   item1, item2, bomb, throw, spell1, spell2.
#                                   Up to 50 in one call; replies once all have
#                                   resolved, with each action's outcome: where
#                                   the player moved from and to, tiles that
#                                   changed nearby (a dug wall), entities within
#                                   12 tiles that moved or died, and its events
#   scenario TYPE X Y [watch=C1,C2] [clear=true] [arena=N] [force=true]
#            [repeat=N] ACTION...
#                                   one whole experiment on the current level:
#                                   optionally carve an arena and clear the
#                                   enemies, spawn TYPE at X Y, perform the
#                                   actions, and reply like `input` plus the
#                                   spawned entity's `watch` components
#                                   (default position, health, aggro) before
#                                   and after. repeat=N (1 to 100) runs it N
#                                   times from the same start, putting the
#                                   player back and healing it between runs,
#                                   and replies with aggregates instead: the
#                                   entity's steps by direction, the beats it
#                                   moved on, its first move, steps toward
#                                   and away from the player, damage taken
#                                   and kills, then one line per run. The coin
#                                   multiplier is not reset. Run `new-run` first
#   step N                          like `input idle` N times, but lists only
#                                   the beats where something happened
#   new-run [CHARACTER] [rhythm=regular]
#                                   start a SingleZone run; rhythm=regular keeps
#                                   the real-time beat, e.g. to see the song end
#   level N
#
# Events (damage taken and dealt, kills, deaths, level loads, song ending or
# ended, coin multiplier lost) go to stderr as `event: {JSON}` lines after the
# next command's reply.
#
# Environment: COTN_LOG, COTN_LOCAL_MODS_DIR, ITJ_BUNDLE_NAME (default
# DevBundle), ITJ_AGENT_BRIDGE_TIMEOUT (seconds, default 30). Run it from
# the dev shell (or `nix run .#agent-bridge --`): the flake supplies
# `wait_for_log` and `install-mods`, and the dev shell sets COTN_LOG and
# COTN_LOCAL_MODS_DIR.
set -euo pipefail

bundleName="${ITJ_BUNDLE_NAME:-DevBundle}"
timeoutSeconds="${ITJ_AGENT_BRIDGE_TIMEOUT:-30}"
rawJson="${ITJ_AGENT_BRIDGE_JSON:-}"

if [[ ${1:-} == --json ]]; then
	rawJson=1
	shift
fi

# Turns a reply's JSON into the compact text form.
read -r -d '' compactFilter <<'EOF' || true
def pos: if .x == null then "(no position)" else "(\(.x),\(.y))" end;
def near($p): (.to // .from) as $e
	| (($e.x - $p.x) | fabs) <= 6 and (($e.y - $p.y) | fabs) <= 6;
def ev: .event + "(" + ([to_entries[]
	| select(.key | IN("event", "level", "turnID", "targetID") | not)
	| "\(.key)=\(.value)"] | join(" ")) + ")";
def entity: "\(.type)#\(.id)" + (if .gone then " gone" else " \(.from | pos)>\(.to | pos)" end);
def action($i): . as $r
	| ["\($i + 1) \(.action)\(if .moved then "+" + (.to | pos) else "=" end)"]
	+ ((.tilesChanged // []) | map("\(.from)>\(.to)@\(pos)"))
	+ ((.events // []) | map(ev))
	+ ((.entitiesMoved // []) | map(select(near($r.to))) | map(entity))
	+ (if .timedOut then ["TIMED-OUT"] else [] end)
	| join("  ");
def tile: "\(.tile // "none") solid=\(.solid) wall=\(.wall) floor=\(.floor)"
	+ (if .digResistance then " dig=\(.digResistance)" else "" end);
def counts: to_entries | sort_by(.key) | map("\(.key):\(.value)") | join(" ");
if has("aggregate") then
	"hp=\(.player.health)/\(.player.maxHealth) at=\(.player | pos) lvl=\(.level) turn=\(.turnID)",
	.aggregate as $a
	| "runs=\($a.runs) moves=\($a.moves) closer=\($a.closer) farther=\($a.farther) damage=\($a.damageTaken) killedRuns=\($a.killedRuns)",
	"steps dx,dy: \($a.stepCounts | counts)",
	"first move beat: \($a.firstMoveBeat | counts)",
	"moves per beat: \($a.moveBeats | counts)",
	(.runs | to_entries[] | "run \(.key + 1): moves=\(.value.steps | join(" ")) beats=\(.value.moveBeats | join(",")) damage=\(.value.damageTaken)"
		+ (if .value.killedOnBeat then " killed@\(.value.killedOnBeat)" else "" end))
elif has("results") then
	"hp=\(.player.health)/\(.player.maxHealth) at=\(.player | pos) lvl=\(.level) turn=\(.turnID)",
	(.results | to_entries[] | .key as $i | .value | action($i)),
	(if .watched then
		"watched \(.watched.before.type)#\(.watched.before.id) before: \(.watched.before.components | tojson)",
		"watched \(.watched.before.type)#\(.watched.before.id) after:  \(.watched.after | if .gone then "gone" else .components | tojson end)"
	else empty end)
elif has("tiles") then
	(.tiles[] | "\(pos) \(tile)")
elif has("tile") or has("solid") then
	"\(pos) \(tile)"
elif has("entities") then
	"count=\(.count)",
	(.entities[] | "\(.type)#\(.id) \(pos)"
		+ (if .components then " \(.components | tojson)" else "" end))
elif has("inventory") then
	"\(.player.type) hp=\(.player.components.health.health)/\(.player.components.health.maxHealth) at=\(.player.components.position | pos) facing=\(.facing // "?") lvl=\(.level) turn=\(.turnID) rhythm=\(.rhythmMode) song=\(.song.time | floor)/\(.song.length | floor)s ended=\(.song.endReached)",
	"chain: x\(.player.components.grooveChain.multiplier) kills=\(.player.components.grooveChain.killCount) gold=\(.player.components.goldCounter.amount)",
	"inv: " + (.inventory | map("\(.type)#\(.id)") | join(" "))
elif has("id") and has("type") then
	"\(.type)#\(.id) \(pos)"
else tojson end
EOF

# The dev shell holds a built copy of this script, but `install-mods` installs
# the mod from the source tree, so after an edit the two can drift apart until
# the shell is re-entered. `builtScriptHash` is set by the nix build.
sourceScript="${ITJ_FLAKE_ROOT:-}/Mods/agent-bridge.bash"
if [[ -n ${builtScriptHash:-} && -f $sourceScript ]]; then
	sourceHash=$(sha256sum "$sourceScript" | cut -d' ' -f1)
	if [[ $sourceHash != "$builtScriptHash" ]]; then
		echo "agent-bridge: warning: this CLI is older than Mods/agent-bridge.bash, so it may lack commands the installed mod has; re-enter the dev shell (or run 'bash Mods/agent-bridge.bash' from it)" >&2
	fi
fi

if [[ ${1:-} == "" ]]; then
	sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
	exit 2
fi

if [[ -z ${COTN_LOG:-} || -z ${COTN_LOCAL_MODS_DIR:-} ]]; then
	echo "agent-bridge: COTN_LOG or COTN_LOCAL_MODS_DIR is unset; run it from the dev shell (nix develop) or as 'nix run .#agent-bridge -- ...'" >&2
	exit 1
fi

modDir="$COTN_LOCAL_MODS_DIR/$bundleName/AgentBridge"

# Commits and `itj-impure-tests` replace the bundle's mods, so any command may
# find AgentBridge gone.
if [[ ! -d $modDir ]]; then
	installBaseline=$(wc -l <"$COTN_LOG")
	ITJ_BUNDLE_RELOAD_TRIGGER="AgentBridge/AgentBridge.lua" install-mods AgentBridge >&2
	if ! wait_for_log "$installBaseline" "[AgentBridge] ready"; then
		echo "agent-bridge: installed AgentBridge but it did not report ready; is the game running?" >&2
		exit 1
	fi
	# One install makes the game load the mod twice a few milliseconds apart,
	# and the second load discards a command sent after the first ready line.
	# So wait until the ready lines stop coming.
	readyCount=0
	while true; do
		sleep 1
		newCount=$(tail -n "+$((installBaseline + 1))" "$COTN_LOG" | grep -acF "[AgentBridge] ready" || true)
		if ((newCount == readyCount)); then
			break
		fi
		readyCount=$newCount
	done
fi

seenFile="$modDir/.events-seen"
id="$(date +%s%N)"
baseline=$(wc -l <"$COTN_LOG")

# Prints the game's events since the previous command to stderr, so that
# stdout stays pure JSON. A log shorter than the remembered position means the
# game restarted.
# shellcheck disable=SC2329 # invoked by the EXIT trap
printEvents() {
	local seen total
	seen=$(cat "$seenFile" 2>/dev/null || echo "$baseline")
	total=$(wc -l <"$COTN_LOG")
	if ((seen > total)); then
		seen=0
	fi
	tail -n "+$((seen + 1))" "$COTN_LOG" |
		grep -aF "[AgentBridge] EVENT " |
		sed -E "s/^.*\[AgentBridge\] EVENT /event: /; s/'?\r?\$//" >&2 || true
	echo "$total" >"$seenFile"
}
replyFile="$(mktemp)"
trap 'rm -f "$replyFile"; printEvents' EXIT
# Rename, so the mod never reads a half-written file.
printf '%s %s\n' "$id" "$*" >"$modDir/.cmd.tmp"
mv "$modDir/.cmd.tmp" "$modDir/cmd.txt"

deadline=$((SECONDS + timeoutSeconds))
while ((SECONDS < deadline)); do
	replies="$(
		tail -n "+$((baseline + 1))" "$COTN_LOG" |
			grep -aF "[AgentBridge] $id " |
			grep -a $'"\r$' |
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
			sed -E 's/^DATA [0-9]+\/[0-9]+ //' <<<"$replies" | tr -d '\n' | base64 -d >"$replyFile"
			echo >>"$replyFile"
			if [[ -n $rawJson ]]; then
				cat "$replyFile"
			else
				jq -r "$compactFilter" "$replyFile"
			fi
			exit 0
		fi
		;;
	esac
	sleep 0.1
done

echo "agent-bridge: no reply in ${timeoutSeconds}s; is the game running with AgentBridge?" >&2
exit 1

# Behavior test for live-game-run: its game-instance lock, its wait for a log
# line (timeout, stall, and the slice of new lines it prints) and its install
# options. Needs no live game: it fakes the log and the mods directory, and
# holds the lock from outside. Expects `live-game-run` on PATH.
set -u

scratch=$(mktemp -d)
lockFile="$scratch/game.lock"
modsDir="$scratch/mods"
mkdir "$modsDir"
touch "$scratch/NecroDancer.log"
holderPid=""
trap '[ -n "$holderPid" ] && kill "$holderPid" 2>/dev/null; rm -rf "$scratch"' EXIT

export ITJ_MODS_ROOT="$scratch/repo/Mods"
export ITJ_GAME_LOCK_FILE="$lockFile"
export COTN_LOCAL_MODS_DIR="$modsDir"
export COTN_LOG="$scratch/NecroDancer.log"

# Two minimal mods, each with the entry script the default reload touches.
for mod in Alpha Beta; do
	mkdir -p "$ITJ_MODS_ROOT/$mod"
	echo "{\"namespace\":\"$mod\",\"name\":\"$mod\",\"synchronyVersion\":\"1.0\"}" >"$ITJ_MODS_ROOT/$mod/mod.json"
	echo "-- $mod" >"$ITJ_MODS_ROOT/$mod/$mod.lua"
done
bundle="$modsDir/DevBundle"

fail() {
	echo "FAIL: $1" >&2
	if [ -n "${2:-}" ]; then
		echo "$2" >&2
	fi
	exit 1
}

# Takes the lock in the background, then holds it for $1 seconds. Returns once
# the holder really holds it, so the test never races the holder's start.
startHolder() {
	rm -f "$scratch/held"
	echo "pid=4242 command=fake-holder" >"$lockFile"
	(
		flock 8
		touch "$scratch/held"
		exec sleep "$1"
	) 8>>"$lockFile" &
	holderPid=$!
	local tries=0
	while [ ! -e "$scratch/held" ]; do
		sleep 0.05
		tries=$((tries + 1))
		if ((tries > 200)); then
			fail "the holder never took the lock"
		fi
	done
}

# Appends $2... to the log, one line per second after a $1-second delay, in
# the background; sets growerPid.
grow() {
	local delay=$1
	shift
	(
		sleep "$delay"
		for line in "$@"; do
			echo "$line" >>"$COTN_LOG"
			sleep 1
		done
	) &
	growerPid=$!
}

# A caller that outwaits its lock timeout fails, names the holder, and installs
# nothing.
startHolder 30
status=0
stderr=$(ITJ_GAME_LOCK_TIMEOUT_SECONDS=1 live-game-run Alpha 2>&1 >/dev/null) || status=$?
if ((status != 3)); then
	fail "a busy lock did not exit 3 (status $status); stderr was:" "$stderr"
fi
if ! grep -qF "fake-holder" <<<"$stderr"; then
	fail "a busy lock did not name the holder; stderr was:" "$stderr"
fi
if [ -n "$(ls -A "$modsDir")" ]; then
	fail "something was installed before the lock was taken"
fi
kill "$holderPid"
wait "$holderPid" 2>/dev/null

# A caller whose timeout outlasts the holder waits, then takes the lock,
# records itself, and installs. Without --until it prints nothing and returns.
startHolder 2
start=$(date +%s)
status=0
stdout=$(ITJ_GAME_LOCK_TIMEOUT_SECONDS=30 live-game-run Alpha Beta 2>/dev/null) || status=$?
elapsed=$(($(date +%s) - start))
if ((status != 0)); then
	fail "a caller that outwaited the holder failed (status $status)"
fi
if ((elapsed < 1)); then
	fail "the caller did not wait for the holder (${elapsed}s)"
fi
if ! grep -qF "command=live-game-run mods=Alpha Beta" "$lockFile"; then
	fail "the caller did not record itself as the holder:" "$(cat "$lockFile")"
fi
if [ -n "$stdout" ]; then
	fail "an install without --until printed on stdout:" "$stdout"
fi
if [ ! -d "$bundle/Alpha" ] || [ ! -d "$bundle/Beta" ]; then
	fail "the mods were not installed: $(ls "$bundle")"
fi

# The reload defaults to the first mod's entry script, and --reload picks
# another; each call appends a fresh trigger comment.
if ! grep -qF -- "-- install-mods trigger" "$bundle/Alpha/Alpha.lua"; then
	fail "the default reload did not touch Alpha/Alpha.lua"
fi
live-game-run --reload Beta/Beta.lua Alpha Beta 2>/dev/null || fail "--reload Beta/Beta.lua failed"
if ! grep -qF -- "-- install-mods trigger" "$bundle/Beta/Beta.lua"; then
	fail "--reload did not touch Beta/Beta.lua"
fi
if grep -qF -- "-- install-mods trigger" "$bundle/Alpha/Alpha.lua"; then
	fail "--reload Beta/Beta.lua also touched the default"
fi

# A reload file the mods lack would reload nothing, so it fails the install.
status=0
stderr=$(live-game-run --reload Alpha/missing.lua Alpha 2>&1 >/dev/null) || status=$?
if ((status != 3)); then
	fail "a missing reload file did not exit 3 (status $status); stderr was:" "$stderr"
fi

# --file creates the file with its multi-line content, and a later install
# without it removes it.
live-game-run --file "Alpha/notes.txt=first line
second=line" Alpha 2>/dev/null || fail "--file failed"
if [ "$(cat "$bundle/Alpha/notes.txt")" != "first line
second=line" ]; then
	fail "--file wrote the wrong content:" "$(cat "$bundle/Alpha/notes.txt")"
fi
live-game-run Alpha 2>/dev/null || fail "a reinstall failed"
if [ -e "$bundle/Alpha/notes.txt" ]; then
	fail "a reinstall without --file kept the file"
fi

# A game whose log goes silent fails fast with exit 2 and the restart
# instruction, and frees the lock.
start=$(date +%s)
status=0
stderr=$(live-game-run --until "never" --stall 2 Alpha 2>&1 >/dev/null) || status=$?
elapsed=$(($(date +%s) - start))
if ((status != 2)); then
	fail "a silent log did not exit 2 (status $status); stderr was:" "$stderr"
fi
if ((elapsed > 6)); then
	fail "a silent log took ${elapsed}s to fail"
fi
if ! grep -qF "game not responding" <<<"$stderr" || ! grep -qF "restart the game" <<<"$stderr"; then
	fail "a silent log did not say the game is not responding; stderr was:" "$stderr"
fi
if ! flock --nonblock "$lockFile" true; then
	fail "the lock was still held after the stall"
fi

# A log that keeps growing is no stall, but outlasting --timeout exits 1.
grow 0 a b c d e f
status=0
stderr=$(live-game-run --until "never" --timeout 3 --stall 2 Alpha 2>&1 >/dev/null) || status=$?
wait "$growerPid"
if ((status != 1)); then
	fail "a growing log without the line did not exit 1 (status $status); stderr was:" "$stderr"
fi
if ! grep -qF "timed out" <<<"$stderr"; then
	fail "a timeout did not say so; stderr was:" "$stderr"
fi

# A log that keeps growing past the stall limit ends at the line, and stdout
# holds exactly the lines this call added.
echo "old line" >>"$COTN_LOG"
grow 1 one two three "the end line" "after"
status=0
stdout=$(live-game-run --until "end line" --stall 2 Alpha 2>/dev/null) || status=$?
wait "$growerPid"
if ((status != 0)); then
	fail "a growing log did not run to the line (status $status); stdout was:" "$stdout"
fi
if [ "$stdout" != "$(printf 'one\ntwo\nthree\nthe end line')" ]; then
	fail "stdout was not exactly the new lines:" "$stdout"
fi

echo "live-game-run test passed"

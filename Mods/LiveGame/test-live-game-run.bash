# Behavior test for live-game-run: its game-instance lock, its check that the
# game loaded the install, its wait for a log line (timeout, stall, and the
# slice of new lines it prints) and its install options. Needs no live game:
# it fakes the game, the log and the mods directory, and holds the lock from
# outside. Expects `live-game-run` on PATH and FAKE_GAME naming
# test-fake-game.bash.
set -u
# shellcheck source=test-fake-game.bash
source "$FAKE_GAME"

scratch=$(mktemp -d)
lockFile="$scratch/game.lock"
modsDir="$scratch/mods"
mkdir "$modsDir"
touch "$scratch/NecroDancer.log"
holderPid=""
fakeGamePid=""
trap '[ -n "$holderPid" ] && kill "$holderPid" 2>/dev/null; [ -n "$fakeGamePid" ] && kill "$fakeGamePid" 2>/dev/null; rm -rf "$scratch"' EXIT

export ITJ_MODS_ROOT="$scratch/repo/Mods"
export ITJ_GAME_LOCK_FILE="$lockFile"
export COTN_LOCAL_MODS_DIR="$modsDir"
export COTN_LOG="$scratch/NecroDancer.log"
# The dev shell turns stamping on; the cases below opt in themselves.
unset ITJ_BUNDLE_STAMP_ALL

# Two minimal mods, each with the entry script the default reload touches.
for mod in Alpha Beta; do
	mkdir -p "$ITJ_MODS_ROOT/$mod"
	echo "{\"namespace\":\"$mod\",\"name\":\"$mod\",\"synchronyVersion\":\"1.0\"}" >"$ITJ_MODS_ROOT/$mod/mod.json"
	echo "-- $mod" >"$ITJ_MODS_ROOT/$mod/$mod.lua"
done
bundle="$modsDir/DevBundle"
frozen="$scratch/frozen"
startFakeGame "$bundle" "$COTN_LOG" "$frozen"

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

# expectSetupFailure WHAT: runs live-game-run with the environment the caller
# set up and expects exit 3, the "failed before the wait" code, with a message
# naming WHAT, and nothing installed.
expectSetupFailure() {
	local what=$1 status=0 stderr
	stderr=$(live-game-run --until "never" --timeout 1 Alpha 2>&1 >/dev/null) || status=$?
	if ((status != 3)); then
		fail "$what did not exit 3 (status $status); stderr was:" "$stderr"
	fi
	if ! grep -qF "$what" <<<"$stderr"; then
		fail "$what was not named; stderr was:" "$stderr"
	fi
	if [ -n "$(ls -A "$modsDir")" ]; then
		fail "something was installed despite $what"
	fi
}

# A missing variable, log or lock directory fails before the wait.
(
	unset COTN_LOCAL_MODS_DIR
	expectSetupFailure COTN_LOCAL_MODS_DIR
) || exit 1
(
	unset COTN_LOG
	expectSetupFailure COTN_LOG
) || exit 1
(
	export COTN_LOG="$scratch/missing.log"
	expectSetupFailure "$COTN_LOG"
) || exit 1
(
	chmod 000 "$COTN_LOG"
	expectSetupFailure "$COTN_LOG"
) || exit 1
chmod 644 "$COTN_LOG"
(
	export ITJ_GAME_LOCK_FILE="$scratch/no-such-dir/game.lock"
	expectSetupFailure "$ITJ_GAME_LOCK_FILE"
) || exit 1

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
# another. Each call prefixes the file's first line with a print of a fresh
# token, keeping its line numbers.
trigger='print("[install-mods] loaded '
if [ "$(sed -n 1p "$bundle/Alpha/Alpha.lua")" = "-- Alpha" ] || ! grep -qF -- "$trigger" "$bundle/Alpha/Alpha.lua"; then
	fail "the default reload did not prefix Alpha/Alpha.lua:" "$(cat "$bundle/Alpha/Alpha.lua")"
fi
if [ "$(wc -l <"$bundle/Alpha/Alpha.lua")" != 1 ] || [[ "$(cat "$bundle/Alpha/Alpha.lua")" != *"; -- Alpha" ]]; then
	fail "the reload changed Alpha/Alpha.lua's lines:" "$(cat "$bundle/Alpha/Alpha.lua")"
fi
live-game-run --reload Beta/Beta.lua Alpha Beta 2>/dev/null || fail "--reload Beta/Beta.lua failed"
if ! grep -qF -- "$trigger" "$bundle/Beta/Beta.lua"; then
	fail "--reload did not touch Beta/Beta.lua"
fi
if grep -qF -- "$trigger" "$bundle/Alpha/Alpha.lua"; then
	fail "--reload Beta/Beta.lua also touched the default"
fi

# A reload file the mods lack would reload nothing, so it fails the install.
status=0
stderr=$(live-game-run --reload Alpha/missing.lua Alpha 2>&1 >/dev/null) || status=$?
if ((status != 3)); then
	fail "a missing reload file did not exit 3 (status $status); stderr was:" "$stderr"
fi

# A reload file that is not Lua cannot print the token, so it fails the
# install.
echo "data" >"$ITJ_MODS_ROOT/Alpha/data.txt"
status=0
stderr=$(live-game-run --reload Alpha/data.txt Alpha 2>&1 >/dev/null) || status=$?
rm "$ITJ_MODS_ROOT/Alpha/data.txt"
if ((status != 3)) || ! grep -qF "not a Lua file" <<<"$stderr"; then
	fail "a non-Lua reload file did not exit 3 naming it (status $status); stderr was:" "$stderr"
fi

# A game that keeps logging but never loads the install fails with exit 4 and
# the instruction to toggle the bundle, rather than reading the stale copy's
# lines, even when they hold the awaited line.
touch "$frozen"
grow 0 a "the end line" b c d e
status=0
stderr=$(ITJ_GAME_RELOAD_SECONDS=3 live-game-run --until "end line" --stall 2 Alpha 2>&1 >/dev/null) || status=$?
wait "$growerPid"
rm "$frozen"
if ((status != 4)); then
	fail "a game that did not load the install did not exit 4 (status $status); stderr was:" "$stderr"
fi
if ! grep -qF "did not load the installed mods" <<<"$stderr" || ! grep -qF "off and on in the game's mods menu" <<<"$stderr"; then
	fail "a game that did not load the install did not say so; stderr was:" "$stderr"
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
if [ "$(grep -vF "[install-mods] loaded" <<<"$stdout")" != "$(printf 'one\ntwo\nthree\nthe end line')" ]; then
	fail "stdout was not exactly the new lines:" "$stdout"
fi

# A line followed by far more log than a pipe holds (64 KB) is still found: a
# reader that quits at the first match would kill the writer with SIGPIPE,
# which pipefail turns into a miss, and the wait would run to its timeout.
# 116 KB did not fail that old wait, as grep reads ahead before it can quit;
# about 1 MB did, every time.
bigFile="$scratch/big.txt"
for _ in $(seq 20000); do
	echo "filler line of about fifty bytes, repeated over and over"
done >"$bigFile"
(
	sleep 1
	{
		echo "the big end line"
		cat "$bigFile"
	} >>"$COTN_LOG"
) &
growerPid=$!
status=0
stdout=$(live-game-run --until "big end line" --timeout 5 --stall 0 Alpha 2>/dev/null) || status=$?
wait "$growerPid"
if ((status != 0)); then
	fail "a line followed by about 1 MB of log was not found (status $status)"
fi
if [ "$(grep -vF "[install-mods] loaded" <<<"$stdout" | sed -n 1p)" != "the big end line" ]; then
	fail "the big log's first new line was wrong:" "${stdout:0:200}"
fi

# ITJ_BUNDLE_STAMP_ALL stamps every installed Lua file, at any depth, with
# the token and its path, keeping its lines; and stderr names each file the
# game did not run (the fake game reads only <mod>/*.lua, so Sub/deep.lua
# stays unloaded) and each older token the log gained.
mkdir -p "$ITJ_MODS_ROOT/Alpha/Sub"
echo "-- deep" >"$ITJ_MODS_ROOT/Alpha/Sub/deep.lua"
grow 1 '[Debug] [info] "[install-mods] loaded 111-1 Beta/Beta.lua"' "the stamped end line"
status=0
stderr=$(ITJ_BUNDLE_STAMP_ALL=1 live-game-run --until "stamped end line" --stall 0 Alpha Beta 2>&1 >/dev/null) || status=$?
wait "$growerPid"
if ((status != 0)); then
	fail "a stamped install failed (status $status); stderr was:" "$stderr"
fi
token=$(sed -n '1s/^print("\[install-mods\] loaded \([^ ]*\) Alpha\/Alpha.lua"); -- Alpha$/\1/p' "$bundle/Alpha/Alpha.lua")
if [ -z "$token" ]; then
	fail "Alpha/Alpha.lua was not stamped with its path:" "$(cat "$bundle/Alpha/Alpha.lua")"
fi
for file in Alpha/Sub/deep.lua Beta/Beta.lua; do
	if [ "$(wc -l <"$bundle/$file")" != 1 ] || ! grep -qF "print(\"[install-mods] loaded $token $file\"); --" "$bundle/$file"; then
		fail "$file was not stamped with the call's token and its path:" "$(cat "$bundle/$file")"
	fi
done
if ! grep -qF "2 of 3 installed Lua files printed token $token" <<<"$stderr"; then
	fail "the stamp check did not count the files that ran; stderr was:" "$stderr"
fi
if ! grep -qF "never printed it: Alpha/Sub/deep.lua" <<<"$stderr"; then
	fail "the stamp check did not name the file that never ran; stderr was:" "$stderr"
fi
if ! grep -qxF "  111-1 Beta/Beta.lua" <<<"$stderr"; then
	fail "the stamp check did not name the older token; stderr was:" "$stderr"
fi
rm -r "$ITJ_MODS_ROOT/Alpha/Sub"

echo "live-game-run test passed"

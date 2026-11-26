# Behavior test for the unit-test entrypoint: its game-instance lock, its
# stall detection and the mods each pass installs. Needs no live game: it
# holds the lock from outside and runs the entrypoint against it.
# Expects `itj-impure-tests` on PATH.
set -u

scratch=$(mktemp -d)
lockFile="$scratch/game.lock"
modsDir="$scratch/mods"
mkdir "$modsDir"
touch "$scratch/NecroDancer.log"
holderPid=""
trap '[ -n "$holderPid" ] && kill "$holderPid" 2>/dev/null; rm -rf "$scratch"' EXIT

# An empty repo root makes the entrypoint's install step fail once it has the
# lock, so it never touches a game.
export ITJ_MODS_ROOT="$scratch/repo/Mods"
export ITJ_GAME_LOCK_FILE="$lockFile"
export COTN_LOCAL_MODS_DIR="$modsDir"
export COTN_LOG="$scratch/NecroDancer.log"
mkdir -p "$ITJ_MODS_ROOT"

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
			echo "FAIL: the holder never took the lock" >&2
			exit 1
		fi
	done
}

# A caller that outwaits its timeout fails, names the holder, and installs
# nothing.
startHolder 30
export ITJ_GAME_LOCK_TIMEOUT_SECONDS=1
status=0
stderr=$(itj-impure-tests 2>&1 >/dev/null) || status=$?

if ((status == 0)); then
	echo "FAIL: entrypoint succeeded while the lock was held" >&2
	exit 1
fi

if ! grep -qF "fake-holder" <<<"$stderr"; then
	echo "FAIL: failure did not name the holder; stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

if [ -n "$(ls -A "$modsDir")" ]; then
	echo "FAIL: something was installed before the lock was taken" >&2
	exit 1
fi
kill "$holderPid"
wait "$holderPid" 2>/dev/null

# A caller whose timeout outlasts the holder waits, then takes the lock and
# gets on to installing (which fails here, by design).
startHolder 2
export ITJ_GAME_LOCK_TIMEOUT_SECONDS=30
start=$(date +%s)
stderr=$(itj-impure-tests 2>&1 >/dev/null) || true
elapsed=$(($(date +%s) - start))

if grep -qF "the game is busy" <<<"$stderr"; then
	echo "FAIL: the caller gave up instead of waiting; stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

if ((elapsed < 1)); then
	echo "FAIL: the caller did not wait for the holder (${elapsed}s)" >&2
	exit 1
fi

if ! grep -qF "command=itj-impure-tests" "$lockFile"; then
	echo "FAIL: the caller did not record itself as the holder" >&2
	exit 1
fi

# A game whose log goes silent mid-run fails the holder fast, with the restart
# instruction, and frees the lock. Needs an install that succeeds, so the repo
# holds two minimal mods.
goodRepo="$scratch/good-repo"
for mod in HelloWorld HelloWorldTests; do
	mkdir -p "$goodRepo/Mods/$mod"
	echo "{\"namespace\":\"$mod\",\"name\":\"$mod\",\"synchronyVersion\":\"1.0\"}" >"$goodRepo/Mods/$mod/mod.json"
done
touch "$goodRepo/Mods/HelloWorldTests/api.lua"
export ITJ_MODS_ROOT="$goodRepo/Mods"
export ITJ_SUITE_STALL_SECONDS=2
export ITJ_GAME_LOCK_TIMEOUT_SECONDS=5
start=$(date +%s)
status=0
stderr=$(itj-impure-tests 2>&1 >/dev/null) || status=$?
elapsed=$(($(date +%s) - start))

if ((status != 1)); then
	echo "FAIL: a silent log did not exit 1 (status $status); stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

if ((elapsed > 6)); then
	echo "FAIL: a silent log took ${elapsed}s to fail" >&2
	exit 1
fi

if ! grep -qF "game not responding" <<<"$stderr"; then
	echo "FAIL: a silent log did not say the game is not responding; stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

if ! flock --nonblock "$lockFile" true; then
	echo "FAIL: the lock was still held after the stall" >&2
	exit 1
fi

# A log that keeps growing is not a stall, even past the stall limit, and the
# sentinel ends the wait.
(
	for _ in 1 2 3 4 5 6; do
		sleep 1
		echo "line" >>"$COTN_LOG"
	done
	echo '[HelloWorldTests] PASS fakeTest' >>"$COTN_LOG"
	echo '[HelloWorldTests] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
) &
growerPid=$!
status=0
stdout=$(itj-impure-tests 2>&1) || status=$?
wait "$growerPid"

if grep -qF "game not responding" <<<"$stdout"; then
	echo "FAIL: a growing log was reported as not responding; output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

if ! grep -qF "All tests pass" <<<"$stdout"; then
	echo "FAIL: a growing log did not run to the sentinel (status $status); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

# A run that printed no PASS/FAIL line at all fails with a clear message,
# rather than exiting silently.
(
	sleep 1
	echo '[HelloWorldTests] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
) &
growerPid=$!
status=0
stdout=$(itj-impure-tests 2>&1) || status=$?
wait "$growerPid"

if ((status == 0)); then
	echo "FAIL: a run with no PASS/FAIL lines succeeded; output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

if ! grep -qF "itj-impure-tests: the pass printed no PASS/FAIL lines" <<<"$stdout"; then
	echo "FAIL: a run with no PASS/FAIL lines gave no message; output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

# A claim test file runs in a pass that installs ClaimTests without HelloWorld,
# whose gameplay code would change the claim test's level.
mkdir -p "$goodRepo/Mods/ClaimTests"
echo '{"namespace":"ClaimTests","name":"ClaimTests","synchronyVersion":"1.0"}' >"$goodRepo/Mods/ClaimTests/mod.json"
touch "$goodRepo/Mods/ClaimTests/weapons.lua"
(
	sleep 1
	echo '[HelloWorldTests] PASS fakeClaimTest' >>"$COTN_LOG"
	echo '[HelloWorldTests] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
) &
growerPid=$!
status=0
stdout=$(itj-impure-tests --files weapons.lua 2>&1) || status=$?
wait "$growerPid"

if ((status != 0)) || [ ! -d "$modsDir/DevBundle/ClaimTests" ] || [ -e "$modsDir/DevBundle/HelloWorld" ]; then
	echo "FAIL: a claim test file did not run with ClaimTests alone (status $status); installed: $(ls "$modsDir/DevBundle"); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

if ! grep -qxF "file: weapons.lua" "$modsDir/DevBundle/HelloWorldTests/selected-test.txt"; then
	echo "FAIL: the claim pass did not select the claim test file" >&2
	exit 1
fi

echo "lock test passed"

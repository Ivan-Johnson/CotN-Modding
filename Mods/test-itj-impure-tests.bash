# Behavior test for the unit-test entrypoint's verdicts and the mods each pass
# installs. Needs no live game: it fakes the log and the mods directory, and
# runs the entrypoint through the real `live-game-run`, whose own lock and wait
# test-live-game-run.bash covers. Expects `itj-impure-tests` on PATH.
set -u

scratch=$(mktemp -d)
modsDir="$scratch/mods"
mkdir "$modsDir"
touch "$scratch/NecroDancer.log"
trap 'rm -rf "$scratch"' EXIT

export ITJ_GAME_LOCK_FILE="$scratch/game.lock"
export COTN_LOCAL_MODS_DIR="$modsDir"
export COTN_LOG="$scratch/NecroDancer.log"

# The repo holds two minimal mods, so each install succeeds.
goodRepo="$scratch/good-repo"
for mod in HelloWorld TestFramework; do
	mkdir -p "$goodRepo/Mods/$mod"
	echo "{\"namespace\":\"$mod\",\"name\":\"$mod\",\"synchronyVersion\":\"1.0\"}" >"$goodRepo/Mods/$mod/mod.json"
done
touch "$goodRepo/Mods/TestFramework/api.lua"
export ITJ_MODS_ROOT="$goodRepo/Mods"
export ITJ_GAME_STALL_SECONDS=2

# A game whose log goes silent fails the run, and the restart instruction
# reaches the user.
status=0
stderr=$(itj-impure-tests 2>&1 >/dev/null) || status=$?

if ((status != 1)); then
	echo "FAIL: a silent log did not exit 1 (status $status); stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

if ! grep -qF "game not responding" <<<"$stderr"; then
	echo "FAIL: a silent log did not say the game is not responding; stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

# A pass whose suite completes with 0 failures passes the run, even when the
# log took longer than the stall limit in total, and its last line totals the
# results.
(
	for _ in 1 2 3 4 5 6; do
		sleep 1
		echo "line" >>"$COTN_LOG"
	done
	echo '[TestFramework] PASS fakeTest' >>"$COTN_LOG"
	echo '[TestFramework] XFAIL fakeKnownBug' >>"$COTN_LOG"
	echo '[TestFramework] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
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

if [ "$(tail -n 1 <<<"$stdout")" != "itj-impure-tests: all tests pass: 1 PASS, 1 XFAIL, 0 FAIL, 0 XPASS" ]; then
	echo "FAIL: a growing log did not end with its totals (status $status); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

# A run that printed no PASS/FAIL line at all fails with a clear message,
# rather than exiting silently.
(
	sleep 1
	echo '[TestFramework] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
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

if [[ "$(tail -n 1 <<<"$stdout")" != "itj-impure-tests: run failed: "* ]]; then
	echo "FAIL: a failed run did not end with its totals; output was:" >&2
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
	echo '[TestFramework] PASS fakeClaimTest' >>"$COTN_LOG"
	echo '[TestFramework] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
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

if ! grep -qxF "file: weapons.lua" "$modsDir/DevBundle/TestFramework/selected-test.txt"; then
	echo "FAIL: the claim pass did not select the claim test file" >&2
	exit 1
fi

echo "itj-impure-tests test passed"

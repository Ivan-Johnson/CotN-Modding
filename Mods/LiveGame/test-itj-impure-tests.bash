# Behavior test for the unit-test entrypoint's verdicts and the mods each pass
# installs. Needs no live game: it fakes the log and the mods directory, and
# runs the entrypoint through the real `live-game-run`, whose own lock and wait
# test-live-game-run.bash covers. Expects `itj-impure-tests` on PATH and
# FAKE_GAME naming test-fake-game.bash.
set -u
# shellcheck source=test-fake-game.bash
source "$FAKE_GAME"

scratch=$(mktemp -d)
modsDir="$scratch/mods"
mkdir "$modsDir"
touch "$scratch/NecroDancer.log"
fakeGamePid=""
trap '[ -n "$fakeGamePid" ] && kill "$fakeGamePid" 2>/dev/null; rm -rf "$scratch"' EXIT

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
# live-game-run counts a stall in whole seconds, so S can fire after S - 1 s;
# a fake pass takes about 1.2 s.
export ITJ_GAME_STALL_SECONDS=3
startFakeGame "$modsDir/DevBundle" "$COTN_LOG" "$scratch/frozen"

# Help prints the usage text and exits 0 without installing anything.
for helpArg in --help -h; do
	status=0
	stdout=$(itj-impure-tests "$helpArg" 2>&1) || status=$?
	if ((status != 0)) || ! grep -q "^Usage: itj-impure-tests" <<<"$stdout" || [ -e "$modsDir/DevBundle" ]; then
		echo "FAIL: $helpArg did not print the usage alone (status $status); output was:" >&2
		echo "$stdout" >&2
		exit 1
	fi
done

# expectUsageError REASON ARG...: the run exits 2 with REASON on stderr and
# installs nothing.
expectUsageError() {
	local reason=$1 stderr status=0
	shift
	stderr=$(itj-impure-tests "$@" 2>&1 >/dev/null) || status=$?
	if ((status != 2)) || ! grep -qF -- "$reason" <<<"$stderr" || [ -e "$modsDir/DevBundle" ]; then
		echo "FAIL: '$*' was not a usage error (status $status); stderr was:" >&2
		echo "$stderr" >&2
		exit 1
	fi
}

# An unknown option is not taken for a test name.
expectUsageError "unknown option --bogus" --bogus
# A run takes no more arguments than its form, so a dropped one never looks
# like a pass.
expectUsageError "unexpected arguments: scratchB scratchC" scratchA scratchB scratchC
expectUsageError "unexpected arguments: b.lua" --files a.lua b.lua
expectUsageError "unexpected arguments: b.lua" --small-samples a.lua b.lua
expectUsageError "--files needs a comma-separated list" --files
expectUsageError "--repeat needs a count from 1 to 9999" --repeat
expectUsageError "--repeat needs a count from 1 to 9999" --repeat 0 --files a.lua
# A count bash would wrap to 0 must not run nothing and pass.
expectUsageError "--repeat needs a count from 1 to 9999" --repeat 18446744073709551616
expectUsageError "unexpected arguments: b.lua" --repeat 2 --files a.lua b.lua

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

# The fixture is not a git repo, so the stale-harness check skips silently.
if grep -qF "lacks these harness commits" <<<"$stderr"; then
	echo "FAIL: a tree outside git warned about harness commits; stderr was:" >&2
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

# loadedCount: how many installs the fake game has loaded so far.
loadedCount() {
	grep -c "\[install-mods\] loaded" "$COTN_LOG"
}

# fakePasses LOADS VERDICT...: completes one pass per VERDICT, each once the
# game has loaded that pass's install, with one result line of that verdict,
# and saves the selection pass I installed as $scratch/pass-I-selection.txt.
# LOADS is loadedCount before the run. Take it in the foreground: an
# argument's $(loadedCount) would run in the background job, where the run's
# first install could land before it is counted.
fakePasses() {
	local verdict loads=$1 pass=0
	shift
	for verdict in "$@"; do
		loads=$((loads + 1))
		pass=$((pass + 1))
		for _ in $(seq 100); do
			if (($(loadedCount) >= loads)); then
				break
			fi
			sleep 0.1
		done
		cp "$modsDir/DevBundle/TestFramework/selected-test.txt" "$scratch/pass-$pass-selection.txt"
		# The next install must land in a later second: rsync's quick check
		# compares size and whole-second mtime, and the reload file of the
		# next pass has the same size.
		sleep 1.1
		echo "[TestFramework] $verdict fakePass${pass}Test" >>"$COTN_LOG"
		if [ "$verdict" = FAIL ]; then
			echo '[TestFramework] Test suite completed: 1 failure(s)' >>"$COTN_LOG"
		else
			echo '[TestFramework] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
		fi
	done
}

# --repeat runs the selection in that many rounds and totals every round.
loads=$(loadedCount)
fakePasses "$loads" PASS PASS &
growerPid=$!
status=0
stdout=$(itj-impure-tests --repeat 2 --files weapons.lua 2>&1) || status=$?
wait "$growerPid"
if ((status != 0)) || [ "$(tail -n 1 <<<"$stdout")" != "itj-impure-tests: all tests pass: 2 PASS, 0 XFAIL, 0 FAIL, 0 XPASS over 2 of 2 rounds" ]; then
	echo "FAIL: --repeat 2 did not total two passing rounds (status $status); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

# A failing round ends the repeats, so the round after it never installs.
loads=$(loadedCount)
fakePasses "$loads" FAIL &
growerPid=$!
status=0
stdout=$(itj-impure-tests --repeat 3 --files weapons.lua 2>&1) || status=$?
wait "$growerPid"
if ((status != 1)) || [ "$(tail -n 1 <<<"$stdout")" != "itj-impure-tests: run failed: 0 PASS, 0 XFAIL, 1 FAIL, 0 XPASS over 1 of 3 rounds" ]; then
	echo "FAIL: --repeat 3 did not stop at its failing first round (status $status); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

# A code test file runs in a pass that installs every mod with code tests, and
# not ClaimTests.
mkdir -p "$goodRepo/Mods/OtherMod"
echo '{"namespace":"OtherMod","name":"OtherMod","synchronyVersion":"1.0"}' >"$goodRepo/Mods/OtherMod/mod.json"
touch "$goodRepo/Mods/HelloWorld/tests.lua" "$goodRepo/Mods/OtherMod/other-tests.lua"
(
	sleep 1
	echo '[TestFramework] PASS fakeCodeTest' >>"$COTN_LOG"
	echo '[TestFramework] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
) &
growerPid=$!
status=0
stdout=$(itj-impure-tests --files other-tests.lua 2>&1) || status=$?
wait "$growerPid"

if ((status != 0)) || [ ! -d "$modsDir/DevBundle/OtherMod" ] || [ ! -d "$modsDir/DevBundle/HelloWorld" ] || [ -e "$modsDir/DevBundle/ClaimTests" ]; then
	echo "FAIL: a code test file did not run with every code-test mod (status $status); installed: $(ls "$modsDir/DevBundle"); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

if ! grep -qxF "expect: tests.lua other-tests.lua" "$modsDir/DevBundle/TestFramework/selected-test.txt"; then
	echo "FAIL: the code pass did not expect every code test file" >&2
	exit 1
fi

# A small-sample run runs both passes, each told which files keep their full
# sample.
loads=$(loadedCount)
fakePasses "$loads" PASS PASS &
growerPid=$!
status=0
stdout=$(itj-impure-tests --small-samples weapons.lua 2>&1) || status=$?
wait "$growerPid"

if ((status != 0)) || ! grep -qF "all tests pass: 2 PASS" <<<"$stdout"; then
	echo "FAIL: a small-sample run did not pass both passes (status $status); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

for pass in 1 2; do
	if ! grep -qxF "small-samples-except: weapons.lua" "$scratch/pass-$pass-selection.txt"; then
		echo "FAIL: pass $pass was not told which files keep their full sample:" >&2
		cat "$scratch/pass-$pass-selection.txt" >&2
		exit 1
	fi
done
if grep -q "^file:" "$scratch/pass-1-selection.txt" || ! grep -qxF "file: weapons.lua" "$scratch/pass-2-selection.txt"; then
	echo "FAIL: a small-sample run did not select every test of each pass" >&2
	exit 1
fi

# Two code test files with one basename would make a file selection ambiguous.
touch "$goodRepo/Mods/OtherMod/tests.lua"
status=0
stdout=$(itj-impure-tests --files tests.lua 2>&1) || status=$?
rm "$goodRepo/Mods/OtherMod/tests.lua"
if ((status == 0)) || ! grep -qF "share the basename tests.lua" <<<"$stdout"; then
	echo "FAIL: a duplicate code test basename was not refused (status $status); output was:" >&2
	echo "$stdout" >&2
	exit 1
fi

# A worktree behind mainline is warned of the harness commits it lacks, and of
# no others, and the run still passes.
export HOME="$scratch"
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.com
git -C "$goodRepo" init -q -b mainline
git -C "$goodRepo" add -A
git -C "$goodRepo" commit -qm base
git -C "$goodRepo" branch topic
echo "-- fix" >>"$goodRepo/Mods/TestFramework/api.lua"
git -C "$goodRepo" commit -qam "harness fix"
touch "$goodRepo/Mods/HelloWorld/hello.lua"
git -C "$goodRepo" add -A
git -C "$goodRepo" commit -qm "mod change"
mkdir -p "$goodRepo/Mods/LiveGame"
touch "$goodRepo/Mods/LiveGame/test-x.bash"
git -C "$goodRepo" add -A
git -C "$goodRepo" commit -qm "offline test"
git -C "$goodRepo" worktree add -q "$scratch/topic-tree" topic

# runClaimPass MODS_ROOT: runs weapons.lua's single pass against MODS_ROOT,
# setting status and stderr.
runClaimPass() {
	(
		sleep 1
		echo '[TestFramework] PASS fakeClaimTest' >>"$COTN_LOG"
		echo '[TestFramework] Test suite completed: 0 failure(s)' >>"$COTN_LOG"
	) &
	growerPid=$!
	status=0
	stderr=$(ITJ_MODS_ROOT=$1 itj-impure-tests --files weapons.lua 2>&1 >/dev/null) || status=$?
	wait "$growerPid"
}

runClaimPass "$scratch/topic-tree/Mods"
if ((status != 0)) || ! grep -qF "harness fix" <<<"$stderr" || ! grep -qF "rebase onto mainline" <<<"$stderr"; then
	echo "FAIL: a worktree behind mainline was not warned of its harness commit (status $status); stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi
if grep -qF "mod change" <<<"$stderr" || grep -qF "offline test" <<<"$stderr"; then
	echo "FAIL: the warning listed commits that touch no harness path; stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

# The checkout on mainline lacks nothing, so it is not warned.
runClaimPass "$goodRepo/Mods"
if ((status != 0)) || grep -qF "lacks these harness commits" <<<"$stderr"; then
	echo "FAIL: a checkout on mainline was warned or failed (status $status); stderr was:" >&2
	echo "$stderr" >&2
	exit 1
fi

echo "itj-impure-tests test passed"

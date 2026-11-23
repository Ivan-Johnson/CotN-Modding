# Takes the game-instance lock, so a test run never overlaps another run or an
# interactive session; then installs the mods, waits for the suite, and prints
# its results. This is the only caller that takes the lock; the root AGENTS.md
# describes the lock and its ITJ_GAME_LOCK_* variables.
#
# Usage: run-tests [TEST_NAME]
# With a name, runs only that test (still from the fixed seed) and fails if no
# registered test has it. Values a test reports with `api.observe` appear as
# `OBSERVED <test> <key>=<value>` lines in the output.
lockFile=${ITJ_GAME_LOCK_FILE:-${COTN_LOCAL_MODS_DIR%/}/itj-game.lock}
lockTimeout=${ITJ_GAME_LOCK_TIMEOUT_SECONDS:-120}

exec 9>>"$lockFile"
if ! flock --timeout "$lockTimeout" 9; then
        echo "itj-impure-tests: the game is busy; gave up after ${lockTimeout}s waiting for $lockFile. Holder:" >&2
        cat "$lockFile" >&2
        exit 1
fi
echo "pid=$$ command=itj-impure-tests started=$(date -Is)" >"$lockFile"

baseline=$(wc -l <"$COTN_LOG")

selectedTest=${1:-}

# The framework reads the name of the one test to run from this file in the
# bundle. install-mods can create any file with any content, so it takes the
# path and content in its generic ITJ_BUNDLE_EXTRA_* variables; with no file
# it removes any left by an earlier named run.
selectedTestFile=""
if [ -n "$selectedTest" ]; then
        selectedTestFile="HelloWorldTests/selected-test.txt"
fi
export ITJ_BUNDLE_EXTRA_FILE="$selectedTestFile"
export ITJ_BUNDLE_EXTRA_CONTENT="$selectedTest"

# Installing appends a timestamp comment to api.lua, rather than to the entry
# script. api.lua is the module every mod under test requires at load-time to
# register its tests, so changing it (forcing a reload) cascades a reload of
# every mod that successfully required it - including HelloWorld - re-running
# their registerTest() calls. This also ensures the suite always reruns even
# if there are no new changes.
export ITJ_BUNDLE_RELOAD_TRIGGER="HelloWorldTests/api.lua"
install-mods HelloWorld HelloWorldTests

# Wait for the tests mod's completion sentinel, rather than a hardcoded sleep
# or a quiet-period guess. The whole suite runs about a hundred tests, so the
# limit is far above a minute. A game that crashed or hung
# stops logging, so a log silent for suiteStallSeconds also ends the wait; the
# longest gap between two log lines inside a healthy run was 36 s, hence 120.
suiteTimeoutSeconds=${ITJ_SUITE_TIMEOUT_SECONDS:-900}
suiteStallSeconds=${ITJ_SUITE_STALL_SECONDS:-120}
waitStatus=0
SECONDS=0
wait_for_log "$baseline" "[HelloWorldTests] Test suite completed" "$suiteTimeoutSeconds" "$suiteStallSeconds" || waitStatus=$?
if ((waitStatus == 1)); then
	echo "itj-impure-tests: timed out waiting for test suite completion" >&2
elif ((waitStatus == 2)); then
	echo "itj-impure-tests: game not responding (no new NecroDancer.log line for ${suiteStallSeconds}s); restart the game and re-run. Last log lines:" >&2
	tail -n 20 "$COTN_LOG" >&2
fi

newOutput="$(tail -n "+$((baseline + 1))" "$COTN_LOG")"
echo "$newOutput"
echo "itj-impure-tests: suite took ${SECONDS} of ${suiteTimeoutSeconds} s"

if ((waitStatus != 0)); then
	echo "Test suite did not complete"
	exit 1
fi

# A test that reports twice was queued twice (a reload registered it again),
# so the run is not the single fixed-seed run the tests assume.
duplicates=$(grep -oE '\[HelloWorldTests\] (PASS|FAIL|XFAIL|XPASS) [A-Za-z0-9_]+' <<<"$newOutput" | sort | uniq -d)
if [ -n "$duplicates" ]; then
        echo "itj-impure-tests: tests reported more than once:" >&2
        echo "$duplicates" >&2
        exit 1
fi

if grep -qE '\[HelloWorldTests\] Test suite completed: 0 failure\(s\)' <<<"$newOutput"; then
        echo All tests pass
else
        echo "itj-impure-tests: test suite reported failures" >&2
        exit 1
fi

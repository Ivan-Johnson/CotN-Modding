# Takes the game-instance lock, so a test run never overlaps another run or an
# interactive session; then installs the mods, waits for the suite, and prints
# its results. This is the only caller that takes the lock.
#
# Usage: run-tests [TEST_NAME]
# With a name, runs only that test (still from the fixed seed) and fails if no
# registered test has it. Values a test reports with `api.observe` appear as
# `OBSERVED <test> <key>=<value>` lines in the output.
#
# ITJ_GAME_LOCK_FILE: the lock file (default: inside the game's mods directory, the one shared writable path).
# ITJ_GAME_LOCK_TIMEOUT_SECONDS: how long to wait for the lock (default 120).
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

# Installing appends a timestamp comment to api.lua, rather than
# to the entry script. api.lua is the module every mod under test
# requires at load-time to register its tests, so changing it
# (forcing a reload) cascades a reload of every mod that
# successfully required it - including HelloWorld - re-running
# their registerTest() calls. This also ensures the suite always
# reruns even if there are no new changes.
selectedTest=${1:-}
extraFile=""
if [ -n "$selectedTest" ]; then
        extraFile="HelloWorldTests/selected-test.txt"
fi

ITJ_BUNDLE_EXTRA_FILE="$extraFile" ITJ_BUNDLE_EXTRA_CONTENT="$selectedTest" \
        ITJ_BUNDLE_RELOAD_TRIGGER="HelloWorldTests/api.lua" install-mods HelloWorld HelloWorldTests

# Wait for the tests mod's completion sentinel, rather than a
# hardcoded sleep or a quiet-period guess.
timedOut=0
if ! wait_for_log "$baseline" "[HelloWorldTests] Test suite completed"; then
        echo "itj-impure-tests: timed out waiting for test suite completion" >&2
        timedOut=1
fi

newOutput="$(tail -n "+$((baseline + 1))" "$COTN_LOG")"
echo "$newOutput"

if ((timedOut)); then
        echo "Test suite timed out"
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

# Takes the game-instance lock, so a test run never overlaps another run or an
# interactive session; then installs the mods, waits for the suite, and prints
# its results. This is the only caller that takes the lock.
#
# Environment:
#   ITJ_MODS_ROOT                  default <git toplevel>/Mods
#   ITJ_GAME_LOCK_FILE             default itj-game.lock in the game's mods dir
#   ITJ_GAME_LOCK_TIMEOUT_SECONDS  wait for another run's lock (default 120)
#   ITJ_SUITE_TIMEOUT_SECONDS      wait for each pass to complete (default 900)
#   ITJ_SUITE_STALL_SECONDS        fail once the log is silent this long
#                                  (default 120)
#
# Usage: itj-impure-tests [TEST_NAME | --files FILE,FILE...]
# With no argument, runs every test. With a name, runs only that test (still
# from the fixed seed) and fails if no registered test has it. With --files,
# runs only the tests registered by the named test files (basenames, e.g.
# weapons.lua), in registration order.
# Values a test reports with `api.observe` appear as
# `OBSERVED <test> <key>=<value>` lines in the output.
#
# A run has up to two passes, each one install and one reload: the code pass
# installs HelloWorld, and the claim pass installs ClaimTests without it, so
# HelloWorld's gameplay code never changes a claim test's level
# (Docs/Adr/0008-claim-tests-run-only-when-their-page-changes.md).
lockFile=${ITJ_GAME_LOCK_FILE:-${COTN_LOCAL_MODS_DIR%/}/itj-game.lock}
lockTimeout=${ITJ_GAME_LOCK_TIMEOUT_SECONDS:-120}

exec 9>>"$lockFile"
if ! flock --timeout "$lockTimeout" 9; then
        echo "itj-impure-tests: the game is busy; gave up after ${lockTimeout}s waiting for $lockFile. Holder:" >&2
        cat "$lockFile" >&2
        exit 1
fi
echo "pid=$$ command=itj-impure-tests started=$(date -Is)" >"$lockFile"

modsRoot="${ITJ_MODS_ROOT:-$(git rev-parse --show-toplevel)/Mods}"
suiteTimeoutSeconds=${ITJ_SUITE_TIMEOUT_SECONDS:-900}
suiteStallSeconds=${ITJ_SUITE_STALL_SECONDS:-120}

claimFiles=()
if [ -d "$modsRoot/ClaimTests" ]; then
        for path in "$modsRoot"/ClaimTests/*.lua; do
                if [ -e "$path" ]; then
                        claimFiles+=("${path##*/}")
                fi
        done
fi

# Set by runPass when the framework reports that no registered test has the
# selected name.
nameMissing=0

# runPass SELECTION MOD...: installs the mods with the framework, runs the
# selection (the framework's selected-test.txt content: empty for every
# registered test, a bare test name, or `file: a.lua b.lua`), prints the new
# log lines and returns non-zero unless every selected test passed.
runPass() {
        local selection=$1
        shift
        local baseline waitStatus newOutput resultLines duplicates
        nameMissing=0
        baseline=$(wc -l <"$COTN_LOG") || return 1

        # The framework reads the selection from this file in the bundle.
        # install-mods can create any file with any content, so it takes the
        # path and content in its generic ITJ_BUNDLE_EXTRA_* variables; with no
        # file it removes any left by an earlier selected run.
        local selectedTestFile=""
        if [ -n "$selection" ]; then
                selectedTestFile="HelloWorldTests/selected-test.txt"
        fi
        export ITJ_BUNDLE_EXTRA_FILE="$selectedTestFile"
        export ITJ_BUNDLE_EXTRA_CONTENT="$selection"

        # Installing appends a timestamp comment to api.lua, rather than to an
        # entry script. api.lua is the module every mod under test requires at
        # load-time to register its tests, so changing it (forcing a reload)
        # cascades a reload of every mod that successfully required it,
        # re-running their registerTest() calls. This also ensures the suite
        # always reruns even if there are no new changes.
        export ITJ_BUNDLE_RELOAD_TRIGGER="HelloWorldTests/api.lua"
        # runPass runs in a `||` list, where errexit is off, so check each step.
        install-mods "$@" HelloWorldTests || return 1

        # Wait for the tests mod's completion sentinel, rather than a hardcoded
        # sleep or a quiet-period guess. A game that crashed or hung stops
        # logging, so a log silent for suiteStallSeconds also ends the wait; the
        # longest gap between two log lines inside a healthy run was 36 s,
        # hence 120.
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
        echo "itj-impure-tests: the pass of $* took ${SECONDS} of ${suiteTimeoutSeconds} s"

        if ((waitStatus != 0)); then
                echo "Test suite did not complete"
                return 1
        fi

        if grep -qF "no registered test has this name" <<<"$newOutput"; then
                nameMissing=1
        fi

        # A test that reports twice was queued twice (a reload registered it
        # again), so the pass is not the single fixed-seed run the tests assume.
        resultLines=$(grep -oE '\[HelloWorldTests\] (PASS|FAIL|XFAIL|XPASS) [A-Za-z0-9_]+' <<<"$newOutput" || true)
        if [ -z "$resultLines" ]; then
                echo "itj-impure-tests: the pass printed no PASS/FAIL lines" >&2
                return 1
        fi
        duplicates=$(sort <<<"$resultLines" | uniq -d)
        if [ -n "$duplicates" ]; then
                echo "itj-impure-tests: tests reported more than once:" >&2
                echo "$duplicates" >&2
                return 1
        fi

        if ! grep -qE '\[HelloWorldTests\] Test suite completed: 0 failure\(s\)' <<<"$newOutput"; then
                echo "itj-impure-tests: test suite reported failures" >&2
                return 1
        fi
}

# Each pass's mods and selection; an empty selection runs every test the
# pass's mods register.
codeSelection=""
claimSelection=""
runCode=1
runClaim=1

if [ "${1:-}" = "--files" ]; then
        if [ -z "${2:-}" ]; then
                echo "itj-impure-tests: --files needs a comma-separated list of test files" >&2
                exit 1
        fi
        codeList=()
        claimList=()
        IFS=, read -ra fileList <<<"$2"
        for file in "${fileList[@]}"; do
                if [ -e "$modsRoot/ClaimTests/$file" ]; then
                        claimList+=("$file")
                else
                        codeList+=("$file")
                fi
        done
        runCode=$((${#codeList[@]} > 0))
        runClaim=$((${#claimList[@]} > 0))
        codeSelection="file: ${codeList[*]}"
        claimSelection="file: ${claimList[*]}"
elif [ -n "${1:-}" ]; then
        codeSelection=$1
        claimSelection=$1
else
        # Without a selection the claim pass would also run the framework's
        # own tests, which the code pass already ran.
        claimSelection="file: ${claimFiles[*]}"
fi
if ((${#claimFiles[@]} == 0)); then
        runClaim=0
fi

status=0
if [ -n "${1:-}" ] && [ "${1:-}" != "--files" ]; then
        # A named test lives in one pass. Try the claim pass first, as most
        # named runs explore the game, and fall back to the code pass.
        if ((runClaim)); then
                runPass "$claimSelection" ClaimTests || status=$?
        fi
        if ((!runClaim || nameMissing)); then
                status=0
                runPass "$codeSelection" HelloWorld || status=$?
        fi
else
        if ((runCode)); then
                runPass "$codeSelection" HelloWorld || status=1
        fi
        if ((runClaim)); then
                runPass "$claimSelection" ClaimTests || status=1
        fi
fi

if ((status != 0)); then
        exit 1
fi
echo All tests pass

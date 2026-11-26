# Runs the live tests: each pass installs its mods through live-game-run,
# which locks the game for that pass, waits for the suite and hands back the
# new log lines; this script prints them and judges the results.
#
# Environment:
#   ITJ_MODS_ROOT  default <git toplevel>/Mods
#   live-game-run's variables (the lock, its timeouts) apply to each pass.
#
# Usage: itj-impure-tests [TEST_NAME | --files FILE,FILE...]
# With no argument, runs every test. With a name, runs only that test (still
# from the fixed seed) and fails if no registered test has it. With --files,
# runs only the tests registered by the named test files (basenames, e.g.
# weapons.lua), in registration order.
# Values a test reports with `api.observe` appear as
# `OBSERVED <test> <key>=<value>` lines in the output.
# The last line totals the run's results, e.g.
# `itj-impure-tests: all tests pass: 132 PASS, 3 XFAIL, 0 FAIL, 0 XPASS`, or
# `run failed:` in place of `all tests pass:`. `build-release` shows the last
# line of a successful run, so keep it last.
#
# A run has up to two passes, each one install and one reload: the code pass
# installs every code-test mod (a mod with a `tests.lua` or `*-tests.lua`), and
# the claim pass installs ClaimTests without them, so their gameplay code never
# changes a claim test's level
# (Docs/Adr/0008-claim-tests-run-only-when-their-page-changes.md). Another
# caller may use the game between the passes, which is safe because each pass
# reinstalls the whole bundle (Docs/Adr/0009-one-module-owns-the-live-game-instance.md).
modsRoot="${ITJ_MODS_ROOT:-$(git rev-parse --show-toplevel)/Mods}"

# The test files of each pass, and the code-test mods, as itj-impure-scope.bash
# also finds them.
claimFiles=()
codeFiles=()
codeMods=()
for path in "$modsRoot"/ClaimTests/*.lua; do
        if [ -e "$path" ]; then
                claimFiles+=("${path##*/}")
        fi
done
# A file selection names test files by basename, so two code test files must
# not share one.
declare -A codeFileMods=()
for path in "$modsRoot"/*/tests.lua "$modsRoot"/*/*-tests.lua; do
        if [ ! -e "$path" ]; then
                continue
        fi
        file=${path##*/}
        mod=${path%/*}
        mod=${mod##*/}
        if [ "$mod" = ClaimTests ]; then
                continue
        fi
        if [ -n "${codeFileMods[$file]:-}" ]; then
                echo "itj-impure-tests: ${codeFileMods[$file]} and $mod share the basename $file" >&2
                exit 1
        fi
        codeFileMods[$file]=$mod
        codeFiles+=("$file")
        if [[ " ${codeMods[*]} " != *" $mod "* ]]; then
                codeMods+=("$mod")
        fi
done

# Set by runPass when the framework reports that no registered test has the
# selected name.
nameMissing=0

# Each verdict's count over every pass, for the summary line.
declare -A counts=([PASS]=0 [XFAIL]=0 [FAIL]=0 [XPASS]=0)

# runPass SELECTION EXPECTED MOD...: installs the mods with the framework and
# runs the selection (empty for every registered test, a bare test name, or
# `file: a.lua b.lua`) once each of the EXPECTED test files (space-separated
# basenames) has registered a test. Prints the new log lines, adds their
# results to counts and returns non-zero unless every selected test passed.
runPass() {
        local selection=$1 expected=$2
        shift 2
        local runStatus newOutput resultLines duplicates runArgs verdict found
        nameMissing=0

        # The framework reads the expected files and the selection from this
        # file in the bundle. The expected files make the suite wait out the
        # reload batches of a changed mod set; see EXPECT_TIMEOUT_TICKS in
        # TestFramework/api.lua.
        #
        # The reload goes through api.lua, rather than an entry script. api.lua
        # is the module every mod under test requires at load-time to register
        # its tests, so changing it cascades a reload of every mod that
        # successfully required it, re-running their registerTest() calls, and
        # the suite reruns even with no new changes.
        #
        # runPass runs in a `||` list, where errexit is off, so check each step.
        runArgs=(--until "[TestFramework] Test suite completed")
        runArgs+=(--reload TestFramework/api.lua)
        runArgs+=(--file "TestFramework/selected-test.txt=expect: $expected
$selection")
        runStatus=0
        newOutput=$(live-game-run "${runArgs[@]}" "$@" TestFramework) || runStatus=$?
        echo "$newOutput"

        # Count before any early return, so a failed pass's results still
        # reach the summary.
        resultLines=$(grep -oE '\[TestFramework\] (PASS|FAIL|XFAIL|XPASS) [A-Za-z0-9_]+' <<<"$newOutput" || true)
        for verdict in "${!counts[@]}"; do
                found=$(grep -c "\] $verdict " <<<"$resultLines" || true)
                counts[$verdict]=$((counts[$verdict] + found))
        done

        # live-game-run has already said why on stderr, including the restart
        # instruction when the game stopped responding.
        if ((runStatus != 0)); then
                echo "Test suite did not complete"
                return 1
        fi

        # Each reload batch reports a missing name again, so stop before the
        # duplicate check.
        if grep -qF "no registered test has this name" <<<"$newOutput"; then
                nameMissing=1
                return 1
        fi

        # A test that reports twice was queued twice (a reload registered it
        # again), so the pass is not the single fixed-seed run the tests assume.
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

        if ! grep -qE '\[TestFramework\] Test suite completed: 0 failure\(s\)' <<<"$newOutput"; then
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
                runPass "$claimSelection" "${claimFiles[*]}" ClaimTests || status=$?
        fi
        if ((!runClaim || nameMissing)); then
                status=0
                runPass "$codeSelection" "${codeFiles[*]}" "${codeMods[@]}" || status=$?
        fi
else
        if ((runCode)); then
                runPass "$codeSelection" "${codeFiles[*]}" "${codeMods[@]}" || status=1
        fi
        if ((runClaim)); then
                runPass "$claimSelection" "${claimFiles[*]}" ClaimTests || status=1
        fi
fi

summary="${counts[PASS]} PASS, ${counts[XFAIL]} XFAIL, ${counts[FAIL]} FAIL, ${counts[XPASS]} XPASS"
if ((status != 0)); then
        echo "itj-impure-tests: run failed: $summary"
        exit 1
fi
echo "itj-impure-tests: all tests pass: $summary"

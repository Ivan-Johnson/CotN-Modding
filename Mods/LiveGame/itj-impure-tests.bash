# Runs the live tests: each pass installs its mods through live-game-run,
# which locks the game for that pass, waits for the suite and hands back the
# new log lines; this script prints them and judges the results.
#
# Usage: `itj-impure-tests --help`; the text lives in usage() below.
# `build-release` shows the last line of a successful run, so keep the totals
# line last.
#
# A run has up to two passes, each one install and one reload: the code pass
# installs every code-test mod (a mod with a `tests.lua` or `*-tests.lua`), and
# the claim pass installs ClaimTests without them, so their gameplay code never
# changes a claim test's level
# (Docs/Adr/0008-claim-tests-run-only-when-their-page-changes.md). Another
# caller may use the game between the passes, which is safe because each pass
# reinstalls the whole bundle (Docs/Adr/0009-one-module-owns-the-live-game-instance.md).
usage() {
        cat <<'EOF'
Usage: itj-impure-tests [--repeat N] [TEST_NAME | --files FILE,FILE... |
                         --small-samples [FILE,FILE...]]
       itj-impure-tests --help

With no argument, runs every test. With a name, runs only that test (still
from the fixed seed) and fails if no registered test has it; it takes one
name, and --files runs several tests. With --files, runs only the tests
registered by the named test files (basenames, e.g. weapons.lua), in
registration order. With --small-samples, runs every test, and each survey
test takes its small sample unless its file is named (`api.smallSample` in
TestFramework/api.lua).

With --repeat N (1 to 9999), runs the selection in N rounds in a row,
stopping at the first round that fails, and totals every round's results;
when N > 1 the last line ends with " over R of N rounds". --repeat comes
first.

Values a test reports with `api.observe` appear as
`OBSERVED <test> <key>=<value>` lines in the output.
The last line totals the run's results, e.g.
`itj-impure-tests: all tests pass: 132 PASS, 3 XFAIL, 0 FAIL, 0 XPASS`, or
`run failed:` in place of `all tests pass:`.

At start it warns on stderr when local `mainline` has harness commits
(`itj-impure-scope --harness-paths`) that this checkout lacks.

Environment:
  ITJ_MODS_ROOT  default <git toplevel>/Mods
  live-game-run's variables (the lock, its timeouts) apply to each pass.
EOF
}

# usageError REASON: exits 2 before anything is installed.
usageError() {
        echo "itj-impure-tests: $1" >&2
        echo "Run 'itj-impure-tests --help' for usage." >&2
        exit 2
}

repeat=1
if [ "${1:-}" = --repeat ]; then
        # A cap on the digits keeps bash from wrapping a huge count to 0, which
        # would run nothing and report a pass.
        if ! [[ "${2:-}" =~ ^[1-9][0-9]{0,3}$ ]]; then
                usageError "--repeat needs a count from 1 to 9999"
        fi
        repeat=$2
        shift 2
fi

# The selection form (all, name, files or small-samples) and the most
# arguments it takes, counting the option itself.
mode=all
maxArgs=0
case "${1:-}" in
-h | --help)
        usage
        exit 0
        ;;
--files)
        mode=files
        maxArgs=2
        if [ -z "${2:-}" ]; then
                usageError "--files needs a comma-separated list of test files"
        fi
        ;;
--small-samples)
        mode=small-samples
        maxArgs=2
        ;;
-*)
        usageError "unknown option $1"
        ;;
"") ;;
*)
        mode=name
        maxArgs=1
        ;;
esac
if (($# > maxArgs)); then
        usageError "unexpected arguments: ${*:maxArgs+1} (one test name per run; --files selects several test files)"
fi

modsRoot="${ITJ_MODS_ROOT:-$(git rev-parse --show-toplevel)/Mods}"

# A checkout's dev shell and TestFramework come from its own commit, so a
# harness fix landed on mainline does not reach a session on an older branch
# until it rebases. Warn rather than fail; skip where there is no local
# mainline (a fork, CI, the nix sandbox).
checkout=$(git -C "$modsRoot" rev-parse --show-toplevel 2>/dev/null) || checkout=""
if [ -n "$checkout" ] && git -C "$checkout" rev-parse --verify --quiet refs/heads/mainline >/dev/null; then
        harnessList=$(itj-impure-scope --harness-paths)
        mapfile -t harnessPaths <<<"$harnessList"
        missing=$(git -C "$checkout" log --format='  %h %s' HEAD..mainline -- "${harnessPaths[@]}" 2>/dev/null) || missing=""
        if [ -n "$missing" ]; then
                echo "itj-impure-tests: warning: this checkout lacks these harness commits from mainline; rebase onto mainline:" >&2
                echo "$missing" >&2
        fi
fi

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
# `file: a.lua b.lua`, optionally followed by a `small-samples-except:` line)
# once each of the EXPECTED test files (space-separated basenames) has
# registered a test. Prints the new log lines, adds their
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

if [ "$mode" = small-samples ]; then
        IFS=, read -ra fullList <<<"${2:-}"
        smallSamples="small-samples-except: ${fullList[*]}"
        codeSelection=$smallSamples
        claimSelection="file: ${claimFiles[*]}
$smallSamples"
elif [ "$mode" = files ]; then
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
elif [ "$mode" = name ]; then
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
round=0
while ((status == 0 && round < repeat)); do
        round=$((round + 1))
        if ((repeat > 1)); then
                echo "itj-impure-tests: round $round of $repeat"
        fi
        if [ "$mode" = name ]; then
                # A named test lives in one pass. Try the claim pass first, as
                # most named runs explore the game, and fall back to the code
                # pass; later rounds skip a claim pass that lacked the name.
                if ((runClaim)); then
                        runPass "$claimSelection" "${claimFiles[*]}" ClaimTests || status=$?
                fi
                if ((!runClaim || nameMissing)); then
                        runClaim=0
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
done

summary="${counts[PASS]} PASS, ${counts[XFAIL]} XFAIL, ${counts[FAIL]} FAIL, ${counts[XPASS]} XPASS"
if ((repeat > 1)); then
        summary="$summary over $round of $repeat rounds"
fi
if ((status != 0)); then
        echo "itj-impure-tests: run failed: $summary"
        exit 1
fi
echo "itj-impure-tests: all tests pass: $summary"

# The one way to drive the live game (ADR 0009). Takes the game-instance lock
# for this call, installs the named mods into the bundle, forces a reload, and
# with --until waits for a log line and prints the new NecroDancer.log lines.
#
# Usage: live-game-run [--until LINE] [--timeout S] [--stall S]
#                      [--reload MOD/FILE] [--file MOD/PATH=CONTENT] MOD...
#
#   --until LINE        wait for a new log line containing LINE, then print
#                       every log line the call added on stdout
#   --timeout S         give up waiting for LINE after S seconds
#   --stall S           give up once the log gains nothing for S seconds,
#                       since a crashed or hung game logs nothing; the
#                       longest silence inside a healthy test run was 36 s,
#                       hence the default 120; 0 turns the check off
#   --reload MOD/FILE   the bundle file to append a timestamp comment to,
#                       which forces the game to reload it and every mod that
#                       requires it; default <first MOD>/<first MOD>.lua
#   --file MOD/PATH=CONTENT
#                       create this file in the bundle, holding CONTENT (which
#                       may span lines), so the mod sees it from its first load
#
# Without --until, it installs and returns. Exit status: 0 when the install
# succeeded and LINE (if given) appeared, 1 when LINE timed out, 2 when the
# game stopped responding, and 3 when the call failed before waiting (bad
# usage, the lock busy, or a failed install). Progress goes to stderr.
#
# Environment:
#   COTN_LOG                       the game's NecroDancer.log
#   COTN_LOCAL_MODS_DIR            the game's local mods directory
#   ITJ_MODS_ROOT                  default <git toplevel>/Mods
#   ITJ_GAME_LOCK_FILE             default itj-game.lock in the game's mods dir
#   ITJ_GAME_LOCK_TIMEOUT_SECONDS  wait for another caller's lock (default 900,
#                                  the default --timeout, so a caller outwaits
#                                  one whole run of another)
#   ITJ_GAME_TIMEOUT_SECONDS       the default --timeout (900)
#   ITJ_GAME_STALL_SECONDS         the default --stall (120)

usage() {
	echo "live-game-run: $1" >&2
	echo "usage: live-game-run [--until LINE] [--timeout S] [--stall S] [--reload MOD/FILE] [--file MOD/PATH=CONTENT] MOD..." >&2
	exit 3
}

untilLine=""
timeoutSeconds=${ITJ_GAME_TIMEOUT_SECONDS:-900}
stallSeconds=${ITJ_GAME_STALL_SECONDS:-120}
reload=""
extraFile=""
extraContent=""
mods=()
while (($# > 0)); do
	case $1 in
	--until | --timeout | --stall | --reload | --file)
		if (($# < 2)); then
			usage "$1 needs a value"
		fi
		case $1 in
		--until)
			untilLine=$2
			;;
		--timeout)
			timeoutSeconds=$2
			;;
		--stall)
			stallSeconds=$2
			;;
		--reload)
			reload=$2
			;;
		--file)
			if [[ -n $extraFile ]]; then
				usage "--file may be given once"
			fi
			if [[ $2 != */*=* ]]; then
				usage "--file needs MOD/PATH=CONTENT, got '$2'"
			fi
			extraFile=${2%%=*}
			extraContent=${2#*=}
			;;
		esac
		shift 2
		;;
	-*)
		usage "unknown option '$1'"
		;;
	*)
		mods+=("$1")
		shift
		;;
	esac
done

if ((${#mods[@]} == 0)); then
	usage "name at least one mod"
fi
if [[ ! $timeoutSeconds =~ ^[0-9]+$ || ! $stallSeconds =~ ^[0-9]+$ ]]; then
	usage "--timeout and --stall take whole seconds"
fi
if [[ -z $reload ]]; then
	reload="${mods[0]}/${mods[0]}.lua"
fi

lockFile=${ITJ_GAME_LOCK_FILE:-${COTN_LOCAL_MODS_DIR%/}/itj-game.lock}
lockTimeout=${ITJ_GAME_LOCK_TIMEOUT_SECONDS:-900}

exec 9>>"$lockFile"
if ! flock --timeout "$lockTimeout" 9; then
	echo "live-game-run: the game is busy; gave up after ${lockTimeout}s waiting for $lockFile. Holder:" >&2
	cat "$lockFile" >&2
	exit 3
fi
echo "pid=$$ command=live-game-run mods=${mods[*]} started=$(date -Is)" >"$lockFile"

baseline=$(wc -l <"$COTN_LOG")

# install-mods's stdout would mix into the log lines this prints.
if ! ITJ_BUNDLE_RELOAD_TRIGGER=$reload ITJ_BUNDLE_EXTRA_FILE=$extraFile ITJ_BUNDLE_EXTRA_CONTENT=$extraContent install-mods "${mods[@]}" >&2; then
	exit 3
fi

if [[ -z $untilLine ]]; then
	exit 0
fi

# Polls the log lines after the baseline for the line, rather than sleeping a
# guessed time. Returns 1 on timeout and 2 once the log has gained no bytes
# for stallSeconds.
waitForLine() {
	local start now lastSize size lastChange
	start=$(date +%s)
	lastChange=$start
	lastSize=$(stat -c %s "$COTN_LOG")
	while ! tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -qF "$untilLine"; do
		sleep 0.1
		now=$(date +%s)
		size=$(stat -c %s "$COTN_LOG")
		if ((size != lastSize)); then
			lastSize=$size
			lastChange=$now
		fi
		if ((stallSeconds > 0 && now - lastChange >= stallSeconds)); then
			return 2
		fi
		if ((now - start >= timeoutSeconds)); then
			return 1
		fi
	done
}

SECONDS=0
waitStatus=0
waitForLine || waitStatus=$?
if ((waitStatus == 1)); then
	echo "live-game-run: timed out after ${timeoutSeconds}s waiting for '$untilLine'" >&2
elif ((waitStatus == 2)); then
	echo "live-game-run: game not responding (no new NecroDancer.log line for ${stallSeconds}s); restart the game and re-run. Last log lines:" >&2
	tail -n 20 "$COTN_LOG" >&2
fi

tail -n "+$((baseline + 1))" "$COTN_LOG"
echo "live-game-run: ${mods[*]} took ${SECONDS} of ${timeoutSeconds} s" >&2
exit "$waitStatus"

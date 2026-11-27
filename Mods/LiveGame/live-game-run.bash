# The one way to drive the live game (ADR 0009). Takes the game-instance lock
# for this call, installs the named mods into the bundle, forces a reload, and
# with --until checks that the game loaded the new copy, waits for a log line
# and prints the new NecroDancer.log lines.
#
# Usage: live-game-run [--until LINE] [--timeout S] [--stall S]
#                      [--reload MOD/FILE] [--file MOD/PATH=CONTENT] MOD...
#
#   --until LINE        wait for the reload, then for a new log line
#                       containing LINE, then print every log line the call
#                       added on stdout
#   --timeout S         give up waiting for LINE after S seconds
#   --stall S           give up once the log gains nothing for S seconds,
#                       since a crashed or hung game logs nothing; the
#                       longest silence inside a healthy test run was 36 s,
#                       hence the default 120; 0 turns the check off
#   --reload MOD/FILE   the bundle Lua file to change, which forces the game
#                       to reload it and every mod that requires it; default
#                       <first MOD>/<first MOD>.lua. The change makes the
#                       file print "[install-mods] loaded <token>" with a
#                       token fresh to this call, so a game that loads the
#                       new copy logs it; it must run when the mod loads
#   --file MOD/PATH=CONTENT
#                       create this file in the bundle, holding CONTENT (which
#                       may span lines), so the mod sees it from its first load
#
# Without --until, it installs and returns. Exit status: 0 when the install
# succeeded and LINE (if given) appeared, 1 when LINE timed out, 2 when the
# game stopped responding, 3 when the call failed before waiting (bad usage,
# a missing variable, log or lock directory, the lock busy, or a failed
# install), and 4 when the game kept logging but did not load the new copy of
# the reload file in time. Progress goes to stderr.
#
# Environment:
#   COTN_LOG                       the game's NecroDancer.log
#   COTN_LOCAL_MODS_DIR            the game's local mods directory
#   ITJ_MODS_ROOT                  default <git toplevel>/Mods
#   ITJ_GAME_LOCK_FILE             default itj-game.lock in the game's mods dir
#   ITJ_GAME_LOCK_TIMEOUT_SECONDS  wait for another caller's lock (default
#                                  the default --timeout, not this call's, so
#                                  a caller outwaits one whole pass of another)
#   ITJ_GAME_TIMEOUT_SECONDS       the default --timeout (900)
#   ITJ_GAME_STALL_SECONDS         the default --stall (120)
#   ITJ_GAME_RELOAD_SECONDS        how long --until waits for the reload
#                                  token (default 30; a reload takes about
#                                  1 s)
#   ITJ_BUNDLE_STAMP_ALL           "1" to make every installed Lua file
#                                  print the token with its path, not just
#                                  the reload file, which reloads every file
#                                  on each install. With --until, once the
#                                  wait ends, stderr names each file that
#                                  never printed this call's token and each
#                                  that printed an older one. A diagnostic
#                                  for reloads that load only part of an
#                                  install; it does not change the exit
#                                  status. The dev shell sets it.

usage() {
	echo "live-game-run: $1" >&2
	echo "usage: live-game-run [--until LINE] [--timeout S] [--stall S] [--reload MOD/FILE] [--file MOD/PATH=CONTENT] MOD..." >&2
	exit 3
}

untilLine=""
defaultTimeout=${ITJ_GAME_TIMEOUT_SECONDS:-900}
timeoutSeconds=$defaultTimeout
stallSeconds=${ITJ_GAME_STALL_SECONDS:-120}
reloadSeconds=${ITJ_GAME_RELOAD_SECONDS:-30}
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
if [[ ! $reloadSeconds =~ ^[0-9]+$ ]]; then
	usage "ITJ_GAME_RELOAD_SECONDS takes whole seconds"
fi
if [[ -z $reload ]]; then
	reload="${mods[0]}/${mods[0]}.lua"
fi

# Under set -u a missing variable or file would exit 1, which reads as a
# timeout, so check them before taking the lock.
if [[ -z ${COTN_LOCAL_MODS_DIR:-} ]]; then
	echo "live-game-run: COTN_LOCAL_MODS_DIR is not set; it names the game's local mods directory" >&2
	exit 3
fi
if [[ -z ${COTN_LOG:-} ]]; then
	echo "live-game-run: COTN_LOG is not set; it names the game's NecroDancer.log" >&2
	exit 3
fi
if [[ ! -r $COTN_LOG ]]; then
	echo "live-game-run: cannot read the game log COTN_LOG=$COTN_LOG" >&2
	exit 3
fi

lockFile=${ITJ_GAME_LOCK_FILE:-${COTN_LOCAL_MODS_DIR%/}/itj-game.lock}
lockTimeout=${ITJ_GAME_LOCK_TIMEOUT_SECONDS:-$defaultTimeout}
if [[ ! -d $(dirname "$lockFile") ]]; then
	echo "live-game-run: the lock file's directory does not exist: $lockFile" >&2
	exit 3
fi

if ! exec 9>>"$lockFile"; then
	echo "live-game-run: cannot open the lock file $lockFile" >&2
	exit 3
fi
if ! flock --timeout "$lockTimeout" 9; then
	echo "live-game-run: the game is busy; gave up after ${lockTimeout}s waiting for $lockFile. Holder:" >&2
	cat "$lockFile" >&2
	exit 3
fi
echo "pid=$$ command=live-game-run mods=${mods[*]} started=$(date -Is)" >"$lockFile"

baseline=$(wc -l <"$COTN_LOG")

# install-mods's stdout would mix into the log lines this prints.
reloadToken="$(date +%s%N)-$$"
export ITJ_BUNDLE_RELOAD_TRIGGER=$reload
export ITJ_BUNDLE_RELOAD_TOKEN=$reloadToken
export ITJ_BUNDLE_EXTRA_FILE=$extraFile
export ITJ_BUNDLE_EXTRA_CONTENT=$extraContent
if ! install-mods "${mods[@]}" >&2; then
	exit 3
fi

if [[ -z $untilLine ]]; then
	exit 0
fi

# waitForLine LINE TIMEOUT: polls the log lines after the baseline for LINE,
# rather than sleeping a guessed time. Returns 1 after TIMEOUT seconds and 2
# once the log has gained no bytes for stallSeconds. grep reads all its input
# rather than quitting at the first match (no -q), so tail never dies of
# SIGPIPE, which pipefail would turn into a miss.
waitForLine() {
	local line=$1 timeout=$2
	local start now lastSize size lastChange
	start=$(date +%s)
	lastChange=$start
	lastSize=$(stat -c %s "$COTN_LOG")
	while ! tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -F "$line" >/dev/null; do
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
		if ((now - start >= timeout)); then
			return 1
		fi
	done
}

SECONDS=0
waitStatus=0
# The game can stop noticing changes to the bundle while still running and
# logging, and then never reloads, so a stale copy of the mods would answer
# the wait. The token is fresh to this call, so seeing it shows the game
# loaded the copy just installed.
waitForLine "[install-mods] loaded $reloadToken" "$reloadSeconds" || waitStatus=$?
if ((waitStatus == 1)); then
	waitStatus=4
	echo "live-game-run: the game did not load the installed mods within ${reloadSeconds}s: $reload never printed its reload token. The game has likely stopped noticing changes to ${ITJ_BUNDLE_NAME:-DevBundle}; turn ${ITJ_BUNDLE_NAME:-DevBundle} off and on in the game's mods menu, or restart the game, and re-run." >&2
elif ((waitStatus == 0)); then
	waitForLine "$untilLine" "$timeoutSeconds" || waitStatus=$?
fi
if ((waitStatus == 1)); then
	echo "live-game-run: timed out after ${timeoutSeconds}s waiting for '$untilLine'" >&2
elif ((waitStatus == 2)); then
	echo "live-game-run: game not responding (no new NecroDancer.log line for ${stallSeconds}s); restart the game and re-run. Last log lines:" >&2
	tail -n 20 "$COTN_LOG" >&2
fi

# reportStamps: under ITJ_BUNDLE_STAMP_ALL, names on stderr each installed
# Lua file that has not printed this call's token, and each stamped line with
# an older token that the log gained since the install.
reportStamps() {
	local bundleDir=${COTN_LOCAL_MODS_DIR%/}/${ITJ_BUNDLE_NAME:-DevBundle}
	local stamps file stale total=0 missing=()
	stamps=$(tail -n "+$((baseline + 1))" "$COTN_LOG" | grep -oE '\[install-mods\] loaded [^ "]+ [^ "]+' || true)
	shopt -s globstar nullglob
	for file in "$bundleDir"/*/**/*.lua; do
		file=${file#"$bundleDir"/}
		total=$((total + 1))
		if ! grep -qxF "[install-mods] loaded $reloadToken $file" <<<"$stamps"; then
			missing+=("$file")
		fi
	done
	echo "live-game-run: stamp check: $((total - ${#missing[@]})) of $total installed Lua files printed token $reloadToken" >&2
	if ((${#missing[@]} > 0)); then
		echo "live-game-run: stamp check: never printed it: ${missing[*]}" >&2
	fi
	stale=$(grep -vF "[install-mods] loaded $reloadToken " <<<"$stamps" | sort -u || true)
	if [[ -n $stale ]]; then
		echo "live-game-run: stamp check: older tokens printed since the install:" >&2
		echo "${stale//\[install-mods\] loaded /  }" >&2
	fi
}

if [[ ${ITJ_BUNDLE_STAMP_ALL:-} == 1 ]] && ((waitStatus != 4)); then
	reportStamps
fi

tail -n "+$((baseline + 1))" "$COTN_LOG"
echo "live-game-run: ${mods[*]} took ${SECONDS} of ${timeoutSeconds} s" >&2
exit "$waitStatus"

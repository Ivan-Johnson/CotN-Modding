# Behavior test for the unit-test entrypoint's game-instance lock. Needs no
# live game: it holds the lock from outside and runs the entrypoint against it.
# Expects `run-tests` on PATH.
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
export ITJ_FLAKE_ROOT="$scratch/repo"
export ITJ_GAME_LOCK_FILE="$lockFile"
export COTN_LOCAL_MODS_DIR="$modsDir"
export COTN_LOG="$scratch/NecroDancer.log"
mkdir "$ITJ_FLAKE_ROOT"

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
stderr=$(run-tests 2>&1 >/dev/null) || status=$?

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
stderr=$(run-tests 2>&1 >/dev/null) || true
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

echo "lock test passed"

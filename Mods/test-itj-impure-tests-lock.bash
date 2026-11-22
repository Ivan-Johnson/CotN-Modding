# Behavior test for the unit-test entrypoint's game-instance lock. Needs no
# live game: it holds the lock from outside, runs the entrypoint with a short
# timeout, and expects a failure that names the holder before anything is
# installed. Expects `run-tests` on PATH.
set -u

scratch=$(mktemp -d)
lockFile="$scratch/game.lock"
modsDir="$scratch/mods"
mkdir "$modsDir"
echo "pid=4242 command=fake-holder" >"$lockFile"

flock "$lockFile" sleep 30 &
holderPid=$!
trap 'kill "$holderPid" 2>/dev/null; rm -rf "$scratch"' EXIT
sleep 0.5

export ITJ_GAME_LOCK_FILE="$lockFile"
export ITJ_GAME_LOCK_TIMEOUT_SECONDS=1
export COTN_LOCAL_MODS_DIR="$modsDir"
export COTN_LOG="$scratch/NecroDancer.log"

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

echo "lock test passed"

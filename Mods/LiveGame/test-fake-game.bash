# Sourced by the offline tests of live-game-run and itj-impure-tests, not a
# test itself: a fake game that "loads" each install by logging the reload
# token install-mods puts at the start of the reload file, as the real game
# does when it runs that file.
#
# startFakeGame BUNDLE LOG FROZEN: polls the Lua files in BUNDLE in the
# background and appends each new token's line to LOG, except while the file
# FROZEN exists, as a game that stopped noticing changes would. Sets
# fakeGamePid; the caller kills it.
startFakeGame() {
	local bundle=$1 log=$2 frozen=$3
	(
		local seen="" file token
		while true; do
			if [ ! -e "$frozen" ]; then
				for file in "$bundle"/*/*.lua; do
					if [ ! -e "$file" ]; then
						continue
					fi
					token=$(sed -n '1s/^print("\[install-mods\] loaded \([^"]*\)").*/\1/p' "$file")
					if [ -n "$token" ] && [[ " $seen " != *" $token "* ]]; then
						seen="$seen $token"
						echo "[Debug] [info] \"[install-mods] loaded $token\"" >>"$log"
					fi
				done
			fi
			sleep 0.1
		done
	) &
	fakeGamePid=$!
}

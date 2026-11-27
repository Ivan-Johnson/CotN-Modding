# Watches the game's log ($COTN_LOG, set by the dev shell) and sends a desktop
# notification when nothing has written to it for more than IDLE_SECONDS
# (default 45), e.g. because the game crashed or hung. It notifies once per
# idle stretch and re-arms once the log is written to again. It polls every 5
# seconds, so a notification comes up to 5 seconds late. A missing log counts
# as idle, so a game restart that recreates it does not stop the watch.
#
# Usage: cotn-log-idle-notify [IDLE_SECONDS]

limit=${1:-45}
log=${COTN_LOG:?COTN_LOG is unset; run this from the dev shell}

notified=0
while sleep 5; do
	now=$(date +%s)
	written=$(stat -c %Y "$log" 2>/dev/null || echo 0)
	idle=$((now - written))
	if ((idle > limit)); then
		if ((!notified)); then
			notify-send -u critical "CotN log idle" "No writes to $(basename "$log") for ${idle}s"
		fi
		notified=1
	else
		notified=0
	fi
done

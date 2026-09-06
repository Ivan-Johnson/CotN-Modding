#!/usr/bin/env bash
#
# Crawl the official Crypt of the NecroDancer modding documentation and push the
# raw HTML to the CotN-docs mirror.
#
# The crawl always runs from scratch and takes about an hour in production mode.
#
# Usage:
#   ./crawl-and-push.sh                     # debug: crawl a tiny subset -> `debug` branch
#   BUILD_MODE=production ./crawl-and-push.sh   # crawl everything -> `mainline` branch

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT
readonly OUTPUT_DIR="$REPO_ROOT/output"
readonly HTML_TARBALL="$OUTPUT_DIR/1-original-html.tar.gz"

readonly START_URL='https://vortexbuffer.com/synchrony/docs/index.html'
readonly MIRROR_REMOTE='git@github.com:Ivan-Johnson/CotN-docs.git'

readonly ACCEPT_REGEX_DEBUG='^.*/docs/(index.html|modules/|modules/necro.client.ClientEvents/|components/|components/necro.game.data.component.character.AutoCastComponents/)$'
readonly ACCEPT_REGEX_PRODUCTION='.*'

# Bad links:
#
# * On this page: https://vortexbuffer.com/synchrony/docs/events/holder/
#
#   Expected: https://vortexbuffer.com/synchrony/docs/events/object
#   Actual:   https://vortexbuffer.com/synchrony/docs/events/events/object
readonly REJECT_REGEX='synchrony/docs/events/events/object'

case "${BUILD_MODE:-debug}" in
	debug)
		accept_regex="$ACCEPT_REGEX_DEBUG"
		branch='debug'
		;;
	production)
		accept_regex="$ACCEPT_REGEX_PRODUCTION"
		branch='mainline'
		;;
	*)
		echo "Invalid BUILD_MODE='$BUILD_MODE' (use BUILD_MODE=debug or BUILD_MODE=production)" >&2
		exit 1
		;;
esac
readonly accept_regex branch

crawl() {
	set -x

	local work="$HTML_TARBALL.work"
	rm -rf "$work"
	mkdir -p "$work"

	# TODO: Figure out what to do with `--wait`.
	wget \
		--recursive \
		--level=inf \
		--wait=3 \
		--continue \
		--convert-links \
		--adjust-extension \
		"--directory-prefix=$work" \
		"--accept-regex=$accept_regex" \
		"--reject-regex=$REJECT_REGEX" \
		"$START_URL"

	tar -zcf "$HTML_TARBALL.tmp" -C "$work" .
	rm -f "$HTML_TARBALL"
	mv "$HTML_TARBALL.tmp" "$HTML_TARBALL"
	chmod -w "$HTML_TARBALL"
	rm -rf "$work"
}

push() {
	local tmp
	tmp="$(mktemp -d)"
	echo "$tmp"

	# Record metadata about this repo before we cd into the temporary clone
	git -C "$REPO_ROOT" rev-parse HEAD > "$tmp/git_HEAD.txt"
	git -C "$REPO_ROOT" diff HEAD > "$tmp/git_diff.txt"
	git -C "$REPO_ROOT" status > "$tmp/git_status.txt"
	date > "$tmp/timestamp.txt"

	tar -zxf "$HTML_TARBALL" -C "$tmp"

	# The temporary directory is deliberately left in place so that a failed or
	# surprising push can be inspected after the fact.
	cd "$tmp"
	git init
	git remote add origin "$MIRROR_REMOTE"
	git fetch origin "$branch"
	git switch --create "$branch"
	git reset --soft "origin/$branch"

	git add .
	git commit -m "Update $(cat timestamp.txt)"
	git push origin "$branch"
}

# Make the directory first, otherwise the logs won't be saved
mkdir -p "$OUTPUT_DIR"
crawl 2>&1 | tee -a "$HTML_TARBALL.log"
push

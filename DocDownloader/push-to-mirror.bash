#!/usr/bin/env bash
#
# Shared by crawl-and-push.bash and push-game-data.bash; source it, don't run it.
#
# `push_to_mirror BRANCH REPO_ROOT STAGE_DIR` makes STAGE_DIR the entire
# contents of BRANCH on the mirror, as one new commit on top of the branch's
# history. It writes provenance for REPO_ROOT into STAGE_DIR first.
#
# `MIRROR_REMOTE` can be overridden, which is how the tests avoid the network.

readonly MIRROR_REMOTE="${MIRROR_REMOTE:-git@github.com:Ivan-Johnson/CotN-docs.git}"

push_to_mirror() {
	local branch="$1"
	local repo_root="$2"
	local stage="$3"

	git -C "$repo_root" rev-parse HEAD > "$stage/git_HEAD.txt"
	git -C "$repo_root" diff HEAD > "$stage/git_diff.txt"
	git -C "$repo_root" status > "$stage/git_status.txt"
	date > "$stage/timestamp.txt"

	# STAGE_DIR is deliberately left in place so that a failed or surprising
	# push can be inspected after the fact.
	cd "$stage"
	git init
	git remote add origin "$MIRROR_REMOTE"
	git switch --create "$branch"

	# A branch's first push has no history to build on.
	if git ls-remote --exit-code --heads origin "$branch" > /dev/null; then
		git fetch origin "$branch"
		git reset --soft "origin/$branch"
	fi

	git add .
	git commit -m "Update $(cat timestamp.txt)"
	git push origin "$branch"
}

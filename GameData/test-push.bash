#!/usr/bin/env bash
#
# Tests for push-game-data.bash and push-to-mirror.bash.
#
# Every push goes to a bare repo in a temporary directory, via `MIRROR_REMOTE`,
# so nothing touches the network or the real mirror.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly under_test="$script_dir/push-game-data.bash"

work="$(mktemp -d)"
readonly work
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null

failures=0
current_case=

fail() {
	echo "  FAIL: $*" >&2
	failures=$((failures + 1))
}

# Start a new case. Sets `repo` to a checkout that has a Tmp/scrape-game-data
# directory with one good scrape, and `MIRROR_REMOTE` to an empty bare repo.
begin() {
	current_case="$1"
	echo "$current_case"

	repo="$work/$current_case/repo"
	mkdir -p "$repo"
	git -C "$repo" init --quiet
	git -C "$repo" commit --quiet --allow-empty -m init

	remote="$work/$current_case/remote.git"
	git init --quiet --bare "$remote"
	export MIRROR_REMOTE="$remote"
	export REPO_ROOT="$repo"

	write_scrape 2026-01-01_00-00-00
}

# `write_scrape NAME` writes a complete scrape under the checkout.
write_scrape() {
	local dir="$repo/Tmp/scrape-game-data/$1"
	mkdir -p "$dir"
	local dataset
	for dataset in necrodancer.xml component-defaults.json entity-prototypes.json script-files.json versions.json; do
		if [[ "$dataset" == *.json ]]; then
			echo "{\"scrape\":\"$1\",\"dataset\":\"$dataset\"}" > "$dir/$dataset"
		else
			echo "$1 $dataset" > "$dir/$dataset"
		fi
	done
	echo "noise" > "$dir/NecroDancer.log"
}

# Succeeds if the push ran. Its output is only wanted when a case fails.
push() {
	bash "$under_test" "$@" > "$work/push.log" 2>&1
}

remote_git() {
	git --git-dir="$remote" "$@"
}

remote_files() {
	remote_git ls-tree -r --name-only "$1"
}

remote_file() {
	remote_git show "$1:$2"
}

# Records a failure unless the pattern was found among the branch's files.
expect_file() {
	remote_files "$1" | grep -qx -- "$2" || fail "$1 lacks $2"
}

expect_no_file() {
	if remote_files "$1" | grep -qx -- "$2"; then
		fail "$1 has $2"
	fi
}

begin pushes-the-datasets-and-provenance
if push; then
	expect_file game-data necrodancer.xml
	expect_file game-data versions.json
	expect_file game-data README.md
	expect_file game-data git_HEAD.txt
	expect_file game-data timestamp.txt
	expect_no_file game-data NecroDancer.log
	[[ "$(remote_file game-data scrape-dir.txt)" == 2026-01-01_00-00-00 ]] || fail "scrape-dir.txt names the wrong scrape"
	remote_file game-data README.md | grep -qi proprietary || fail "README.md doesn't mention the licensing risk"
else
	fail "push failed: $(cat "$work/push.log")"
fi

begin pretty-prints-json-datasets
echo '{"a":[1,2],"b":{"c":"d"}}' > "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00/component-defaults.json"
if push; then
	[[ "$(remote_file game-data component-defaults.json | wc -l)" -gt 1 ]] || fail "component-defaults.json is still one line"
	[[ "$(remote_file game-data component-defaults.json | tr -d ' \n')" == '{"a":[1,2],"b":{"c":"d"}}' ]] || fail "formatting changed the content or key order"
else
	fail "push failed: $(cat "$work/push.log")"
fi

begin refuses-invalid-json
echo '{"truncated":' > "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00/entity-prototypes.json"
if push; then
	fail "pushed a scrape with invalid JSON"
fi
if remote_git rev-parse --verify --quiet game-data > /dev/null; then
	fail "something was pushed anyway"
fi

begin defaults-to-the-newest-scrape
write_scrape 2026-02-02_00-00-00
if push; then
	[[ "$(remote_file game-data scrape-dir.txt)" == 2026-02-02_00-00-00 ]] || fail "did not pick the newest scrape"
else
	fail "push failed: $(cat "$work/push.log")"
fi

begin accepts-an-explicit-scrape
write_scrape 2026-02-02_00-00-00
if push "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00"; then
	[[ "$(remote_file game-data scrape-dir.txt)" == 2026-01-01_00-00-00 ]] || fail "ignored the scrape it was given"
else
	fail "push failed: $(cat "$work/push.log")"
fi

begin a-second-push-replaces-the-contents
push || fail "first push failed"
write_scrape 2026-03-03_00-00-00
if push; then
	[[ "$(remote_git rev-list --count game-data)" == 2 ]] || fail "second push did not build on the first"
	[[ "$(remote_file game-data scrape-dir.txt)" == 2026-03-03_00-00-00 ]] || fail "second push kept the old scrape"
else
	fail "second push failed: $(cat "$work/push.log")"
fi

begin leaves-other-branches-alone
git -C "$repo" commit --quiet --allow-empty -m other
git -C "$repo" push --quiet "$remote" HEAD:refs/heads/mainline
before="$(remote_git rev-parse mainline)"
push || fail "push failed"
[[ "$(remote_git rev-parse mainline)" == "$before" ]] || fail "mainline moved"

begin refuses-a-missing-dataset
rm "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00/necrodancer.xml"
if push; then
	fail "pushed a scrape with no necrodancer.xml"
fi
remote_git rev-parse --verify --quiet game-data > /dev/null && fail "something was pushed anyway"

begin refuses-an-empty-dataset
: > "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00/versions.json"
if push; then
	fail "pushed a scrape with an empty versions.json"
fi

begin refuses-a-scrape-the-mod-flagged
echo "[ScrapeGameData] ERROR versions.json: boom" >> "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00/NecroDancer.log"
if push; then
	fail "pushed a scrape whose log has an ERROR"
fi

begin refuses-a-scrape-without-a-log
rm "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00/NecroDancer.log"
if push; then
	fail "pushed a scrape with no log"
fi

begin refuses-when-there-are-no-scrapes
rm -r "$repo/Tmp/scrape-game-data/2026-01-01_00-00-00"
if push; then
	fail "pushed with nothing to push"
fi

if ((failures > 0)); then
	echo "$failures failure(s)" >&2
	exit 1
fi
echo "all passed"

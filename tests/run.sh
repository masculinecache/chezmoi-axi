#!/usr/bin/env bash
# Hermetic test suite for chezmoi-axi.
#
# Runs ./chezmoi-axi against a mocked `chezmoi` binary on PATH and a temp HOME,
# asserting observable TOON output and exit codes — no live home state touched.
#
# Usage: bash tests/run.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${REPO_ROOT}/chezmoi-axi"
MOCK_DIR="${REPO_ROOT}/tests/mock"

PASS=0
FAIL=0
CURRENT=""

# --- tiny assert harness ---

note() { CURRENT="$1"; }

fail() {
  echo "FAIL - ${CURRENT}: $1"
  FAIL=$((FAIL + 1))
}

ok() { PASS=$((PASS + 1)); }

# assert_contains <haystack> <needle>
assert_contains() {
  if [[ "$1" == *"$2"* ]]; then ok; else fail "expected output to contain '$2'"; fi
}

# assert_not_contains <haystack> <needle>
assert_not_contains() {
  if [[ "$1" != *"$2"* ]]; then ok; else fail "expected output NOT to contain '$2'"; fi
}

# assert_rc <expected> <actual>
assert_rc() {
  if [[ "$2" -eq "$1" ]]; then ok; else fail "expected exit code $1, got $2"; fi
}

# --- environment setup ---

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

HOME_DIR="${WORK}/home"
FIXTURE="${WORK}/fixture"
SRC="${HOME_DIR}/.local/share/chezmoi"
mkdir -p "${HOME_DIR}" "${FIXTURE}" "${SRC}"

export HOME="$HOME_DIR"
export CHEZMOI_FIXTURE="$FIXTURE"
export PATH="${MOCK_DIR}/bin:${PATH}"
# Deploy-key SSH export in sync must not touch the real key during tests.
export GIT_SSH_COMMAND=""

seed_managed() { printf '%s\n' "$@" > "${FIXTURE}/managed.txt"; }
seed_changed() { printf '%s\n' "$@" > "${FIXTURE}/changed.txt"; }

run_wrapper() {
  "$WRAPPER" "$@" 2>/dev/null
}

# ============================================================================
# status: content-first home view
# ============================================================================

note "status with no args is content-first (not help)"
seed_managed "dot_bashrc" "dot_tmux.conf"
out=$(run_wrapper status || true)
assert_contains "$out" "chezmoi:"
assert_contains "$out" "  bin:"
assert_contains "$out" "  description:"
assert_contains "$out" "  managed: 2"
assert_not_contains "$out" "Commands:"

note "bare invocation defaults to status"
out=$(run_wrapper || true)
assert_contains "$out" "chezmoi:"
assert_contains "$out" "  managed: 2"

note "status shows aggregate counts"
out=$(run_wrapper status || true)
assert_contains "$out" "  managed: 2"
assert_contains "$out" "  changed: 0"
assert_contains "$out" "  encrypted: 0"
assert_contains "$out" "  last_sync: never"

note "status with a git source dir computes last_sync"
git_init_src() {
  mkdir -p "${SRC}/.git"
  # .chezmoi-sync marker not needed; mock returns epoch from MOCK_GIT_EPOCH
  export MOCK_GIT_EPOCH="$(( $(date +%s) - 7200 ))"
}
git_init_src
out=$(run_wrapper status || true)
assert_contains "$out" "  last_sync: 2h ago"
unset MOCK_GIT_EPOCH

# ============================================================================
# list
# ============================================================================

note "list emits a TOON table with minimal schema"
seed_managed "dot_bashrc" "dot_config_age" "dot_tmux.conf"
out=$(run_wrapper list || true)
assert_contains "$out" "files[3]{path,type,encrypted}:"
assert_contains "$out" "  ~/.bashrc,file,no"

note "list --encrypted filters encrypted files"
printf 'encrypted_foo.age\n' > "${SRC}/encrypted_foo.age"
out=$(run_wrapper list --encrypted || true)
assert_contains "$out" "files[1]{path,type,encrypted}:"
assert_contains "$out" "~/foo"

note "list --changed filters changed files"
seed_changed "dot_bashrc"
out=$(run_wrapper list --changed || true)
assert_contains "$out" "files[1]{path,type,encrypted}:"
assert_contains "$out" "  dot_bashrc,"

note "list with no managed files is a definitive empty state"
: > "${FIXTURE}/managed.txt"
out=$(run_wrapper list || true)
assert_contains "$out" "files: 0 all files found"
assert_rc 0 "$?"

note "list truncates at 50 rows but --full shows every file"
seed_managed $(seq -f "dot_file%02g.conf" 1 60)
out=$(run_wrapper list || true)
assert_contains "$out" "... (60 total, showing first 50)"
assert_contains "$out" "chezmoi-axi list --full"
out_full=$(run_wrapper list --full || true)
assert_contains "$out_full" "files[60]{path,type,encrypted}:"
assert_not_contains "$out_full" "showing first 50"

# ============================================================================
# diff & apply & verify
# ============================================================================

note "diff with no changes is a definitive empty state"
seed_changed ""
out=$(run_wrapper diff || true)
assert_contains "$out" "diffs: 0 files with changes"
assert_rc 0 "$?"

note "diff lists changed files with summary"
seed_changed "dot_bashrc"
out=$(run_wrapper diff || true)
assert_contains "$out" "diffs:"
assert_contains "$out" "  dot_bashrc"
assert_contains "$out" "summary: 1 files, +0 -0"

note "apply --preview delegates to diff"
seed_changed "dot_bashrc"
out=$(run_wrapper apply --preview || true)
assert_contains "$out" "diffs:"

note "verify reports clean state"
out=$(run_wrapper verify || true)
assert_contains "$out" "verify: all tracked files match source state"

note "verify reports drift and exits 1"
printf 'dot_bashrc\n' > "${FIXTURE}/drifted.txt"
rc=0
out=$(run_wrapper verify) || rc=$?
assert_contains "$out" "verify: 1 files have drifted"
assert_rc 1 "$rc"
rm -f "${FIXTURE}/drifted.txt"

# ============================================================================
# add
# ============================================================================

note "add requires at least one file (usage error, exit 2)"
rc=0
out=$(run_wrapper add) || rc=$?
assert_contains "$out" "error: no files specified"
assert_rc 2 "$rc"

note "add reports missing file with structured error"
out=$(run_wrapper add "${WORK}/nope" 2>/dev/null) || true
assert_contains "$out" "error: file not found"

note "add emits TOON added + summary"
printf 'tracked\n' > "${HOME_DIR}/tracked.txt"
out=$(run_wrapper add "${HOME_DIR}/tracked.txt" || true)
assert_contains "$out" "added: ~/tracked.txt"
assert_contains "$out" "summary: 1 added, 0 skipped"

# ============================================================================
# re-add
# ============================================================================

note "re-add with nothing to do reports in sync / empty"
out=$(run_wrapper re-add 2>/dev/null) || true
assert_contains "$out" "re-added: 0 files (no changes detected)"

# ============================================================================
# sync
# ============================================================================

note "sync up to date when no remote commits"
out=$(run_wrapper sync 2>/dev/null) || true
assert_contains "$out" "sync: already up to date"

note "sync --force applies even with no remote commits"
out=$(run_wrapper sync --force 2>/dev/null) || true
assert_contains "$out" "sync: pulled and applied (force)"

note "sync stamps start and end audit lines"
printf 'x\n' > "${FIXTURE}/remote_commits.txt"
out=$(run_wrapper sync --force 2>/dev/null) || true
assert_contains "$out" "chezmoi-axi sync start"
assert_contains "$out" "chezmoi-axi sync end rc=0"
rm -f "${FIXTURE}/remote_commits.txt"

# --- sync branch guard ---

reset_sync_fixtures() {
  rm -f "${FIXTURE}/current_branch.txt" "${FIXTURE}/dirty.txt" \
        "${FIXTURE}/local_commits.txt" "${FIXTURE}/remote_commits.txt" \
        "${FIXTURE}/checkout.log"
}

note "sync guard fails on dirty feature branch (exit 1, structured error)"
reset_sync_fixtures
echo "feature" > "${FIXTURE}/current_branch.txt"
echo " M dot_bashrc" > "${FIXTURE}/dirty.txt"
rc=0
out=$(run_wrapper sync) || rc=$?
assert_contains "$out" "error: sync blocked: branch 'feature' has live work"
assert_contains "$out" "uncommitted: true"
assert_contains "$out" "sync --branch feature"
assert_rc 1 "$rc"
# Guard must NOT have switched branches
assert_not_contains "$out" "checked out: master"

note "sync guard fails on unpushed commits (names stranded count)"
reset_sync_fixtures
echo "feature" > "${FIXTURE}/current_branch.txt"
printf 'aaa111 local work 1\nbbb222 local work 2\n' > "${FIXTURE}/local_commits.txt"
rc=0
out=$(run_wrapper sync) || rc=$?
assert_contains "$out" "error: sync blocked: branch 'feature' has live work"
assert_contains "$out" "unpushed: 2"
assert_contains "$out" "uncommitted: false"
assert_rc 1 "$rc"

note "sync auto-checks out default branch when feature branch is clean and merged"
reset_sync_fixtures
echo "feature" > "${FIXTURE}/current_branch.txt"
out=$(run_wrapper sync 2>/dev/null) || true
assert_contains "$out" "checked out: master (branch 'feature' was clean and merged)"
assert_contains "$out" "sync: already up to date"
[[ -f "${FIXTURE}/checkout.log" && "$(cat "${FIXTURE}/checkout.log")" == "master" ]] && ok || fail "expected checkout of master recorded"
reset_sync_fixtures

note "sync treats a branch with only a local merge commit as fully merged"
reset_sync_fixtures
echo "feature" > "${FIXTURE}/current_branch.txt"
echo "eee999 Merge branch 'master' into feature" > "${FIXTURE}/local_commits.txt"
out=$(run_wrapper sync 2>/dev/null) || true
assert_contains "$out" "checked out: master (branch 'feature' was clean and merged)"
assert_not_contains "$out" "sync blocked"
reset_sync_fixtures

note "sync --branch escape hatch syncs a non-default branch explicitly"
reset_sync_fixtures
echo "master" > "${FIXTURE}/current_branch.txt"
out=$(run_wrapper sync --branch feature 2>/dev/null) || true
assert_contains "$out" "checked out: feature"
assert_contains "$out" "sync: already up to date"
assert_not_contains "$out" "sync blocked"
[[ -f "${FIXTURE}/checkout.log" && "$(cat "${FIXTURE}/checkout.log")" == "feature" ]] && ok || fail "expected checkout of feature recorded"
reset_sync_fixtures

note "sync --branch without a name is a usage error"
rc=0
out=$(run_wrapper sync --branch) || rc=$?
assert_contains "$out" "error: --branch requires a branch name"
assert_rc 2 "$rc"

# ============================================================================
# help / unknown flags
# ============================================================================

note "unknown flag rejects loudly with exit 2 and lists valid flags"
rc=0
out=$(run_wrapper list --bogus) || rc=$?
assert_contains "$out" "error: unknown flag: --bogus"
assert_rc 2 "$rc"

note "--help per command exits 0 and shows usage"
out=$(run_wrapper list --help || true)
assert_contains "$out" "Usage: chezmoi-axi list"
assert_rc 0 0

note "help subcommand shows command list"
out=$(run_wrapper help || true)
assert_contains "$out" "Commands:"
assert_contains "$out" "status"

note "unknown command exits 2"
rc=0
out=$(run_wrapper bogusxyz) || rc=$?
assert_contains "$out" "error: unknown command: bogusxyz"
assert_rc 2 "$rc"

# ============================================================================
# summary
# ============================================================================

echo ""
echo "chezmoi-axi tests: ${PASS} passed, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
exit 0

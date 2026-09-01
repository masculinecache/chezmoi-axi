# chezmoi-axi

Agent-ergonomic TOON wrapper around [chezmoi](https://www.chezmoi.io/) for token-efficient dotfiles management.

`chezmoi-axi` is a thin, [AXI](https://toonformat.dev/)-compliant bash CLI that wraps the `chezmoi` binary and emits
[TOON](https://toonformat.dev/) on stdout — compact, token-efficient output that agents can consume without a
JSON-parsing round trip. It stays close to chezmoi's own command surface: anything you would do with `chezmoi`
you can do with `chezmoi-axi`, plus predictable list schemas, definitive empty states, aggregate counts, content
truncation with a `--full` escape hatch, and structured errors with actionable suggestions.

## Install

Copy the single self-contained script to a directory on `PATH`:

```sh
install -m 0755 chezmoi-axi ~/.local/bin/chezmoi-axi
```

Requires the `chezmoi` binary on `PATH` (install it with `brew install chezmoi`, your distro package manager, or
[the official installer](https://www.chezmoi.io/install/)). The wrapper resolves the chezmoi source directory from
`$HOME` at runtime (default `~/.local/share/chezmoi`), so it works on any machine without editing the script.

## Usage

```
chezmoi-axi <command> [args]
```

Run with no arguments to see the home view (content first — live state, not a manual).

```
$ chezmoi-axi
chezmoi:
  bin: ~/.local/bin/chezmoi-axi
  description: Agent-ergonomic chezmoi wrapper for dotfiles management
  managed: 1039
  changed: 2
  encrypted: 38
  last_sync: 2h ago
help[3]:
  Run `chezmoi-axi list --changed` to see pending changes
  Run `chezmoi-axi diff` to review diffs
  Run `chezmoi-axi list` to see all managed files
```

Every subcommand supports `--help` (and `-h`) with a concise usage summary. Unknown flags fail loudly, list the
valid flags, and exit `2` so the agent self-corrects in one step.

## Commands

### `status`

Home view — shows current state at a glance. This is the default when run with no arguments.

```
$ chezmoi-axi status
```

Outputs managed count, pending-diff count, encrypted count, and last sync time (derived from the most recent
commit in the chezmoi source). The `bin:` line collapses paths under `$HOME` to `~`.

### `list`

List managed files with a minimal schema: `path`, `type`, `encrypted`.

```
$ chezmoi-axi list
files[5]{path,type,encrypted}:
  ~/.bashrc,shell,no
  ~/.config/opencode/opencode.json,json,no
  ~/.config/opencode/.groq-key,file,maybe
  ~/.ssh/config,ssh,no
  ~/.tmux.conf,config,no
count: 5 of 1039 total
help[2]:
  Run `chezmoi-axi add <file>` to track a new file
  Run `chezmoi-axi diff` to review changes
```

| Sub | Meaning |
| --- | --- |
| `list` | All managed files |
| `list --changed` | Only files with pending diffs |
| `list --encrypted` | Only encrypted (age) files |
| `list --full` | Show every file (bypass the 50-row cap) |

When the result exceeds 50 rows, the list is truncated to the first 50 and a help hint points at `--full` to see
all of them. An empty result is stated explicitly:

```
files: 0 changed files found
help[1]:
  Run `chezmoi-axi list` to see all managed files
```

### `diff`

Show differences between source state and installed files.

```
$ chezmoi-axi diff
chezmoi-axi diff              # all diffs
chezmoi-axi diff <file>       # diff for a specific file
```

Output is a TOON summary with one row per changed file plus aggregate counts:

```
diffs:
  .bashrc
  .tmux.conf
summary: 2 files, +12 -3
help[2]:
  Run `chezmoi-axi apply` to apply these changes
  Run `chezmoi-axi apply --preview` to dry-run first
```

`diff <file>` for a path not managed by chezmoi returns a structured error (exit `1`) with a suggestion to `add`
it. An empty diff reports `diffs: 0 files with changes` (exit `0`).

### `add`

Add a file to chezmoi source state. Idempotent — no error if already tracked (exit `0`).

```
$ chezmoi-axi add ~/.config/app/config.json
added: ~/.config/app/config.json
summary: 1 added, 0 skipped
help[2]:
  Run `chezmoi-axi diff` to verify no drift
  Run `chezmoi-axi commit` to commit and push
```

| Flag | Meaning |
| --- | --- |
| `--encrypt`, `-e` | Encrypt the file with age before adding |

Already-managed files report `already managed:` and count as skipped, not failed. A missing file reports
`error: file not found:`.

### `re-add`

Capture on-disk changes back to source state. Runs `chezmoi re-add --dry-run --verbose` first and branches on the
tool's feedback.

```
$ chezmoi-axi re-add ~/.bashrc
$ chezmoi-axi re-add --all      # re-add all changed files
```

| Flag | Meaning |
| --- | --- |
| `--all`, `-a` | Re-add all changed files |

Verdicts per file:

- **`re-added: <file>`** — change captured to source state.
- **`skipped: template-managed`** — the source is a `.tmpl`; re-add cannot merge live-file edits into a
  template, so it skips (exit `0`). Edit the template directly and verify with
  `chezmoi execute-template < src | diff - <target>`.
- **`in sync: <file>`** — nothing to capture.

Summary: `summary: N re-added, N skipped (template-managed), N in sync`.

### `apply`

Apply source state to installed files.

```
$ chezmoi-axi apply              # apply
$ chezmoi-axi apply --preview    # dry run — shows what would change
```

| Flag | Meaning |
| --- | --- |
| `--preview`, `-n` | Show what would change without applying (runs `diff`) |

On success: `applied: changes applied successfully`. On failure: structured `error: chezmoi apply failed` with a
`help` hint to `diff`.

### `verify`

Check that installed files match source state. Exit `0` if clean, `1` if drifted.

```
$ chezmoi-axi verify
verify: all tracked files match source state
help[2]:
  Run `chezmoi-axi list` to see managed files
  Run `chezmoi-axi diff` to check for pending changes
```

When drift is detected, it reports the count and returns exit `1` (which agents can branch on):

```
verify: 2 files have drifted from source state
help[2]:
  Run `chezmoi-axi diff` to see what changed
  Run `chezmoi-axi re-add --all` to capture changes
```

### `sync`

Pull remote changes and apply. Combines `git fetch` + `chezmoi update`.

```
$ chezmoi-axi sync               # fetch + apply
$ chezmoi-axi sync --preview     # fetch + diff, no apply
$ chezmoi-axi sync --force       # apply without prompting (resolves local drift, for cron)
$ chezmoi-axi sync --branch dev  # sync a non-default branch explicitly
```

| Flag | Meaning |
| --- | --- |
| `--preview`, `-n` | Fetch remote and show the diff without applying |
| `--force`, `-f` | Apply without prompting (resolves local drift; for cron) |
| `--branch <name>` | Sync `<name>` instead of the default branch (escape hatch; checks the branch out if needed) |

**Branch guard.** Sync only auto-checks out the default branch (`master`, detected from
`origin/HEAD`) when the current branch is not the default. Before switching it checks for
(a) uncommitted changes and (b) local work not yet in `origin/master` — HEAD is fully merged
when it is an ancestor of `origin/master` or its only local commits are merge commits. If
either check fails, sync **fails without switching or pulling** and reports a structured error
naming the branch, the stranded commit count, and the recovery command:

```
error: sync blocked: branch 'feature' has live work (uncommitted: true, unpushed: 2)
help[2]:
  recover: commit or push on 'feature', then rerun `chezmoi-axi sync`
  deliberate: run `chezmoi-axi sync --branch feature` to sync this branch anyway
```

Only a clean, fully-merged branch (all work already in `origin/master`, merge commits
included) is auto-checked out to the default branch. To sync a
non-default branch deliberately, pass `--branch <name>`.

Every sync stamps ISO-8601 `start` and `end` lines — the `end` line carries the exit code — so the periodic
crontab log is auditable:

```
[2026-08-28T09:15:00+0200] chezmoi-axi sync start
[2026-08-28T09:15:03+0200] chezmoi-axi sync end rc=0
```

Before running, sync rotates the canonical cron log `~/.local/share/chezmoi/.chezmoi-sync.log` to `.old` once it
exceeds 512 KiB (override with `CHEZMOI_SYNC_LOG_MAX` bytes); other redirections are untouched. It also exports a
passphrase-free `GIT_SSH_COMMAND` deploy key so sync never prompts — safe for cron, agents, and headless contexts.

### `commit` [message]

Stage all chezmoi changes, commit, push, and open a PR. Uses conventional commits.

```
$ chezmoi-axi commit                          # auto-generated message
$ chezmoi-axi commit "feat(app): add new config"
```

If the working tree is clean it reports `commit: nothing to commit` (exit `0`). Otherwise it auto-generates a
`chore(dotfiles): update N managed files` message when none is given, pushes a timestamped branch, and opens a PR
against `master` via `gh`.

## Output

Structured data is emitted as TOON on **stdout**. Errors also go to stdout, in a structured form with an
actionable suggestion, and map to a stable exit code:

| Exit | Meaning |
| --- | --- |
| `0` | success (including no-ops and empty results) |
| `1` | runtime error (e.g. file not found, drift detected, apply/sync failed) |
| `2` | usage error (unknown flag, missing required arg, unknown command) |

```
$ chezmoi-axi list --bogus
error: unknown flag: --bogus
help: chezmoi-axi list [--changed] [--encrypted] [--full]
```
(exit 2)

Unknown flags fail loudly and list the valid flags so the agent self-corrects in one step. `--help` is always
allowed. No command prompts interactively — every operation is completable with flags alone. chezmoi's own
errors are translated into the structured format above and raw dependency stack traces are never leaked to
stdout.

## Integrations

`chezmoi-axi` follows the AXI ambient-context pattern: run it with no arguments (or `status`) to get a compact
home-view dashboard that can be surfaced to an agent at session start. The same output powers the
[installable skill](https://github.com/masculinecache/chezmoi-axi/blob/master/skills/chezmoi-axi/SKILL.md), which lets
agents work with chezmoi through a stable TOON interface.

## Development

```sh
bash -n chezmoi-axi                  # syntax check
shellcheck -S error chezmoi-axi      # static analysis (error level)
./tests/run.sh                       # test suite (bash only, no dependencies)
```

The test suite runs the executable through its public CLI surface (list, diff, add, re-add, sync, verify,
structured errors, exit codes) against a mock `chezmoi` binary — no real dotfiles or network required.

## License

MIT

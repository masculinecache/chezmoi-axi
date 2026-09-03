# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

## Safety: the live home is radioactive

SAFETY RULE (chezmoi incident 2026-09-02 on another server): never run chezmoi or chezmoi-axi against the real host state; no command may read or write ~/.local/share/chezmoi, ~/.config/chezmoi, or live $HOME dotfiles; all tests/demos hermetic (fake HOME via mktemp -d, CHEZMOI_SOURCE_DIR inside the disposable worktree); anything not hermetic gets cut, not pointed at the live home.

In this repo (a 2026-09-02 incident on another host crippled a machine by running repo tooling against the LIVE chezmoi state):

- NEVER run `chezmoi` or `chezmoi-axi` against real host state: no command that reads or writes
  `~/.local/share/chezmoi`, `~/.config/chezmoi`, or `$HOME` dotfiles. Treat those paths as radioactive.
- ALL tests and demos run hermetically: fake `HOME` (`mktemp -d`) so `CHEZMOI_SRC="${HOME}/.local/share/chezmoi"`
  resolves inside the sandbox, mock `chezmoi` on `PATH` (`tests/mock/bin`), no network
  `chezmoi init`/`apply` against real remotes.
- If a test or script cannot be made hermetic, cut it and note it in the PR — never point anything at the live home.

## Test

Run the suite (bash only, no deps; runs the executable's public CLI against a mock `chezmoi`):

```sh
./tests/run.sh
```

## Exit-code contract

Success/no-op is `0`, runtime errors (file not found, drift, apply/sync failure) are `1`, usage errors (unknown
flag, missing arg, unknown command) are `2`. `usage_error()` in `chezmoi-axi` exits `2` for the usage paths;
`die()` exits `1` for runtime paths. Keep this split — tests assert it.

## No hardcoded home paths

`$HOME` is resolved at runtime (`CHEZMOI_SRC="${HOME}/.local/share/chezmoi"`). Never hardcode an absolute
`/home/<user>` path in this repo.

## GitHub credentials

CREDENTIAL RULE: every GitHub operation on this repo uses the masculinecache account ONLY - never the global phillias credentials. Every gh/gh-axi call exports GH_CONFIG_DIR=$HOME/.config/gh-masculinecache (repo .mise.toml already sets it for mise-hooked shells). git push flows through the repo-local credential helper; never alter it. Any gh auth failure: stop and report blocked; never switch credentials.

- Repo `.mise.toml` also pins `GH_REPO` (HOME-relative values only: `~` or `$HOME`, never absolute paths);
  never bare `gh` on ambient config.
- The repo-local credential helper is a blank reset plus the masculinecache `gh auth git-credential` helper
  for `https://github.com`; leave it exactly as configured.

## npm packaging

- Published as scoped `@masculinecache/chezmoi-axi` with `publishConfig.access: public` (scoped packages default
  to restricted). Bash CLI: no build step; `bin` maps `chezmoi-axi` to the script itself (0755, bash shebang).
- Verify packaging hermetically: `npm publish --dry-run` (tarball must contain only `chezmoi-axi`, `LICENSE`,
  `README.md`, `package.json`) and a clean-prefix install (`npm i -g . --prefix <tmp>` → `chezmoi-axi --help`),
  both under a fake `HOME` so no real state is touched.
- Publish is owned by firstmate (granular token must cover the `@masculinecache` scope); when a CI publish job
  is added, follow the wrangler-axi `.github/workflows/publish.yml` precedent.

# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

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

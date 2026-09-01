# Roam

Notes for anyone working in this repo, human or agent. Tool-agnostic on
purpose: `AGENTS.md` is the file the CLI coding agents all read, so there is
no vendor-specific instructions file here.


## Prose and comments

Comments earn their place. Prefer clear code, and keep commentary near 9% of
non-blank lines in Rust and 5% in TypeScript.

- Document a constraint the code cannot show for itself: a wire format, a
  hardware quirk, an ordering requirement, a bug being worked around.
- Do not narrate the line below, and do not justify the alternative you did not
  pick. That is a design diary, not documentation.
- Avoid the rhetorical register: "load-bearing", "the whole point", "worth
  noting", "turns out", "by design", "note that", and the adverbs
  "deliberately", "silently", "actually".
- Keep every functional comment. `SAFETY:`, `eslint-disable`,
  `@ts-expect-error`, `clippy::`, doctest fences and licence headers are code,
  not prose.
- Never use an em-dash, in comments, docs, commit messages, log lines or UI
  copy. Use a comma, a full stop, or parentheses.
- Commit messages follow the same rules and carry no tool-attribution trailers
  (`Co-Authored-By`, `Claude-Session`) and no vendor names.

## Formatting is enforced by a pre-commit hook

`.githooks/pre-commit` formats every staged `.rs` file and re-stages it, so a
commit always contains formatted code. It is committed to the repo, but
`core.hooksPath` is per-clone local config, so **each clone needs one command**:

```sh
git config core.hooksPath .githooks
```

Without it the hook silently does nothing. `git config --get core.hooksPath`
tells you whether this clone is wired up.

The hook is narrow by design:

- It formats only the files being committed, never the whole crate, so
  unrelated in-progress work in the tree is left alone.
- It judges the **staged** content (`git show :file`), not the working tree.
  Those differ whenever a file is partially staged, and the staged blob is what
  the commit will contain.
- It refuses to touch a file with **both** staged and unstaged changes, and
  blocks the commit instead. Formatting the working tree and `git add`-ing it
  would sweep the unstaged edits into the commit.
- It resolves the edition per file from the nearest `Cargo.toml`, since rustfmt
  parses according to an edition.
- `third_party/`, `vendor/` and `target/` are excluded.

To format by hand, `cargo fmt` in `backend/`, but note it rewrites the whole
crate, so when someone else has uncommitted work, format just your own files:

```sh
rustfmt --edition 2024 src/database.rs src/server.rs
cargo fmt --check          # reports diffs without writing
```

## Deploying the backend

Deploys are manual and run from the **repository root**, not from `backend/`,
because the Docker build context needs both `backend/` and `docs/src/pages`:

```sh
fly deploy . --config backend/fly.toml --dockerfile backend/Dockerfile
```

`--dockerfile` is required because the `dockerfile` path inside `fly.toml`
resolves relative to that file rather than to the build context.

A push to `main` does **not** deploy. The `Deploy` workflow (`deploy-fly.yml`)
is written to trigger on that push but is disabled at the repository level;
check with `gh workflow list --all` before assuming a push shipped anything.

## Backend specifics

`backend/Readme.md` is the reference for the crash-review API, the auto-review
rules, and regenerating the `.sqlx` offline query cache. Two things from it
that are easy to get wrong:

- Regenerate the query cache with `cargo sqlx prepare -- --lib --tests`.
  Dropping `--tests` silently discards the cache entries for `query_as!` calls
  in `#[cfg(test)]` code, and `SQLX_OFFLINE=true cargo test` then fails to
  compile.
- `cargo sqlx prepare` rewrites the entire `.sqlx` directory. Diff the result
  before committing and confirm the delta is only the queries you changed.

## Crash triage

`scripts/roam_crashes.py` wraps the backend's crash-review API: list unreviewed
crashes, read threads, stream symbolicated reports, post replies, mark threads
reviewed. It needs `BACKEND_URL` and `BACKEND_API_KEY`, both in `backend/.env`:

```sh
set -a && . ./backend/.env && set +a
python3 scripts/roam_crashes.py --help
```

`.claude/skills/roam-crash-triage/SKILL.md` documents the same workflow in more
detail and is loaded automatically by Claude Code; it is readable directly by
any other tool.

# Skill: gga-branch-pr

## Purpose
Standardize branch creation and PR submission for the GGA project.

## When to Use
When creating a pull request, opening a PR, or preparing changes for review.

## Branch Naming
Format: `type/description` — validated by regex:

```
^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert|hot|rel)\/[a-z0-9._-]+$
```

| Type | Example |
|------|---------|
| feat | `feat/ollama-streaming` |
| fix | `fix/hook-marker-injection` |
| docs | `docs/contributing-labels` |
| chore | `chore/update-shellspec` |
| refactor | `refactor/cache-lookup` |
| test | `test/integration-ci-mode` |
| ci | `ci/split-test-jobs` |
| style | `style/output-formatting` |
| perf | `perf/cache-lookup-speed` |
| build | `build/makefile-targets` |
| revert | `revert/broken-hook-change` |
| hot | `hot/fix-token-refresh` |
| rel | `rel/v2-10-1` |

**Rules**: description must be lowercase, only `a-z`, `0-9`, `.`, `_`, `-`.

## PR Workflow

1. Create branch from main: `git checkout -b type/description main`
2. Make changes following relevant skills (shellcheck-standards, testing-coverage)
3. Run validation: `make lint && make test`
4. Push branch: `git push -u origin type/description`
5. Create PR: `gh pr create --title "type(scope): description" --body "..."`

## PR Title Format
Must match conventional commits regex:

```
^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9\._-]+\))?!?: .+
```

Valid scopes: `providers`, `hooks`, `cache`, `cli`, `ci`, `config`, `install`

Examples:
- `feat(providers): add GitHub Models provider support`
- `fix: crash on startup`
- `fix!: change hook marker format`

## PR Body Template
```
## Summary
<!-- What does this PR do? -->

## Changes
- 

## Testing
- [ ] `make lint` passes
- [ ] `make test` passes

Closes #N
```

## Critical Rules
- Every PR MUST link an approved issue: `Closes #N` in the body
- Every PR MUST have exactly one `type:*` label
- NEVER include `Co-Authored-By` trailers of any kind
- Run `make lint && make test` before pushing — no exceptions
- PRs against unapproved issues will be closed without review

## Cookbook

| If... | Then... | Example |
|-------|---------|---------|
| Creating a bug fix PR | branch: `fix/description`, label: `type:bug` | `fix/cache-hash-collision` |
| Creating a feature PR | branch: `feat/description`, label: `type:feature` | `feat/github-models-provider` |
| Creating a docs PR | branch: `docs/description`, label: `type:docs` | `docs/installation-windows` |
| Creating a refactor PR | branch: `refactor/description`, label: `type:refactor` | `refactor/provider-dispatch` |
| Creating a test PR | branch: `test/description`, label: `type:test` | `test/hook-injection-edge-cases` |

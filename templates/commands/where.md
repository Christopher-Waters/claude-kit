Show which environments a work item is currently deployed to. Usage: `/where <work-item-id>`

Parse `$ARGUMENTS` to extract the work item ID. Accept formats like `AB#1234`, `#1234`, or just `1234`. If no ID is provided, report the error and stop.

## Step 1: Fetch the Work Item

Read the work item from Azure DevOps using the project from the current repo's CLAUDE.md configuration. Expand with `relations` so PR links are included.

If the work item is not found, report the error and stop.

Capture: id, title, type, state, and any linked Pull Request artifacts from `relations`.

## Step 2: Resolve the Environment Chain

Read the **Pipeline Configuration** table from the current repo's `CLAUDE.md`. The table rows define the branches in promotion order (top → bottom). The **first row is the compare branch** (`main`) — feature PRs merge there, but nothing deploys from it; the rows below are the environment branches. Example:

```
| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| main | — (compare branch, no deployment) | — |
| dev | Dev | ... |
| test | Test | ... |
| staging | Staging | ... |
| prod | Production | ... |
```

If the table is missing, report that the project has no pipeline configuration in `CLAUDE.md` and stop.

For each environment branch, run `git fetch origin <branch>` first so the local view is current.

## Step 3: Find the Commits for This Work Item

Locate the commits associated with the work item using these signals (combine results, dedupe by SHA):

1. **Linked PRs** — for each linked PR from Step 1, get the merge commit on the target branch (Azure DevOps API: `lastMergeCommit`).
2. **Commit message search** — `git log --all --grep="AB#<id>\b" --grep="#<id>\b" -i --format=%H` to catch commits whose messages reference the ID.
3. **Branch name** — `git log --all --format=%H` filtered to commits whose source branch matched `*AB#<id>-*` (use `git for-each-ref` + reflog if needed; skip if not resolvable).

If no commits are found, report:
```
AB#<id>: <title>
No commits found referencing this work item — not deployed to any environment.
```
and stop.

## Step 4: Check Each Environment

For each branch in the Pipeline Configuration table, determine whether **any** of the work item's commits is reachable from `origin/<branch>`:

```
git merge-base --is-ancestor <commit> origin/<branch>
```

A work item is "in" an environment if at least one of its commits is an ancestor of that environment's branch tip. Track which specific commits landed in which environment so partial deployments are visible.

## Step 5: Display the Result

Output a concise summary in plain language followed by a details block.

```
AB#<id>: <title>
<type> · <state>

This work item is in <env list joined with " and ">.
```

Where `<env list>` is the environments where the work item is present, in promotion order. The compare branch is not an environment: if the commits are on `main` only, say "merged to main, not deployed to any environment yet." If not even on `main`, say "not merged yet."

Then a details table:

```
| Environment | Branch  | Present | Commits |
|-------------|---------|---------|---------|
| — (compare) | main    | Yes     | 2 of 2  |
| Dev         | dev     | Yes     | 2 of 2  |
| Test        | test    | Yes     | 2 of 2  |
| Staging     | staging | Yes     | 1 of 2  |
| Production  | prod    | No      | 0 of 2  |
```

- **Present**: Yes if at least one commit is reachable from the branch tip; No otherwise. For the compare branch this means "merged", not "deployed".
- **Commits**: how many of the work item's commits are present on that branch (e.g. `1 of 2` flags a partial cherry-pick).

If any linked PRs are still open (not merged), append:

```
Open PRs:
- PR #<n> → <target branch> (<status>)
```

Finally, compare the work item's state with its furthest environment (`dev` → `Ready for Testing`, `test` → `Testing`, `staging` → `Staging`, `prod` → `Deployed`). If the state lags — e.g. commits on `staging` but the item is still `Testing` — add one line: `⚠ State lags environment: Testing, expected at least Staging — /status AB#<id> can catch it up.`

That's it — read-only. Do not modify branches, push, create PRs, or change states.

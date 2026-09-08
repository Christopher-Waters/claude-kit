Check the status of a release, pipeline, environment, or work item. Usage: `/track <target>`

Parse `$ARGUMENTS` to determine what to check:
- **Release**: "release 24" or "r24" → show release status
- **Pipeline**: "pipeline" or "build" → show recent pipeline runs
- **Work item**: "AB#1234" or "1234" → show work item status
- **Environment**: "dev", "test", "staging", or "prod" → show what's deployed
- **No argument**: show an overview of everything

Read the project's `CLAUDE.md` **Pipeline Configuration** table for the branch chain. The first row is the compare branch (`main` — feature PRs merge there; **nothing deploys from it**); the rows below are environment branches in promotion order (`dev → test → staging → prod`). Do not hardcode branch names.

## Environment ↔ State Reference

Work item states track environments. Use this to spot **state lag** — an item whose commits are on a branch but whose state hasn't caught up:

| Commits are on… | State should be at least… |
|---|---|
| `main` | `Code Review` |
| `dev` | `Ready for Testing` |
| `test` | `Testing` |
| `staging` | `Staging` |
| `prod` | `Deployed` |

`Ready for Staging` and `Ready to Deploy` are human sign-offs and are never "lag". Only User Stories, Bugs, and Hot Fixes are checked — Features and Tasks have no environment state.

## If Release (e.g., `/track release 24`):

Query all work items tagged `release-{N}` or in the `Release #{N}` iteration. For each, find which environment branches contain its commits (`repo_search_commits` with `includeWorkItems: true`, or `git merge-base --is-ancestor`).

```
## Release #24 Status

| ID | Type | Title | State | Furthest Environment |
|----|------|-------|-------|----------------------|
| AB#4521 | User Story | Add payment export | Deployed | Production |
| AB#4522 | User Story | Bulk approval workflow | Staging | Staging |
| AB#4530 | User Story | Dashboard trends | Testing | Staging ⚠ |
| AB#4589 | Bug | Login plus sign fix | Closed | Production |

Deployed to:
- Dev: All 4 items
- Test: All 4 items
- Staging: All 4 items
- Production: 2 of 4 items (AB#4521, AB#4589)

⚠ State lag:
- AB#4530 is on `staging` but still in `Testing` — expected at least `Staging`.

Catch these up? (yes/no)
```

If the user says yes, set `System.State` on each lagging item to the expected state via `wit_update_work_item` — never backward, never on a Feature or Task — and report `Was → Now`.

## If Pipeline (e.g., `/track pipeline` or `/track build`):

Query recent builds for each pipeline in the Pipeline Configuration table.

```
## Recent Pipeline Runs

| Pipeline | Branch | Status | Time | Build # |
|----------|--------|--------|------|---------|
| Compass API (YAML) | prod | Succeeded | 2026-09-06 14:26 | 20260906.1 |
| Compass Client (YAML) | prod | Succeeded | 2026-09-06 14:27 | 20260906.1 |
| Compass API (YAML) | test | Succeeded | 2026-09-05 10:15 | 20260905.3 |
```

A run on `main` would be unexpected — `main` has no pipeline. If one appears, say so.

## If Work Item (e.g., `/track AB#4521`):

Read the work item from Azure DevOps and show its full status, including which environment branches contain its commits.

```
## AB#4521: Admin Can Export Payment History to CSV

**Type:** User Story
**State:** Staging
**Assigned To:** Chris Waters
**Release:** Release #24
**Branch:** story/AB#4521-admin-can-export-payment-history
**PR:** #287 (merged to main)

### Environments
| Environment | Branch | Present |
|-------------|--------|---------|
| — (compare) | main | Yes — PR #287 merged 2026-09-01 |
| Dev | dev | Yes — PR #290 merged 2026-09-02 |
| Test | test | Yes — PR #291 merged 2026-09-03 |
| Staging | staging | Yes — PR #295 merged 2026-09-05 |
| Production | prod | No |

State `Staging` matches the furthest environment. ✓

### Child Tasks
| ID | Title | State |
|----|-------|-------|
| AB#4525 | Add export API endpoint | Closed |
| AB#4526 | Add CSV service | Closed |
| AB#4527 | Add export button UI | Closed |
```

If the state lags the furthest environment, flag it and offer to catch it up as in the release view.

## If Environment (e.g., `/track staging`):

Map the name to its branch through the Pipeline Configuration table. Show the last deployment and what's currently there.

```
## Staging Environment

**Branch:** staging
**Last deployment:** 2026-09-05 15:30 (Build #20260905.2)
**Pipeline:** Compass API (YAML) — Succeeded

### Recent merges to staging:
| Commit | Message | Date |
|--------|---------|------|
| a1b2c3d | Release #24 → Staging | 2026-09-05 |
| d4e5f6a | Cherry-pick AB#4601 → Staging | 2026-09-06 |

### Not yet promoted from test:
{count} commits on `test` are not on `staging` — run `/promote test staging` or `/deploy-release <N> staging`.
```

`/track main` is allowed but reports "compare branch — nothing deploys from main" and lists what's on `main` that hasn't been promoted to `dev`.

## If No Argument (e.g., `/track`):

Show a high-level overview.

```
## Project Status

### Active Releases
| Release | Work Items | Furthest Environment |
|---------|-----------|----------------------|
| Release #24 | 6 items | Staging |
| Release #23 | 4 items | Production |

### Environment Chain
| Branch | Environment | Behind previous by |
|--------|-------------|--------------------|
| main | — (compare) | — |
| dev | Dev | 0 commits |
| test | Test | 3 commits |
| staging | Staging | 3 commits |
| prod | Production | 9 commits |

### Recent Pipelines
| Pipeline | Last Run | Branch | Status |
|----------|----------|--------|--------|
| Compass API (YAML) | 20260906.1 | prod | Succeeded |
| Compass Client (YAML) | 20260906.1 | prod | Succeeded |

### Open PRs
| PR # | Title | Target |
|------|-------|--------|
| #292 | AB#4601: Fix bulk approval | main |
| #296 | Promote test → staging | staging |
```

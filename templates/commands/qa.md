Regression-test a work item in a real browser against a running environment. Usage: `/qa <work-item-id> [environment] [--role=<role>] [--screens=/a,/b]`

Parse `$ARGUMENTS` to extract the work item ID. Accept formats like `AB#1234`, `#1234`, or just `1234`. If no ID is provided, report the error and stop.

- **Environment**: optional — `local`, `dev`, `test`, or `staging`. Defaults to `dev`.
- **`--role=<role>`**: optional — which test account to sign in as. Defaults to the row marked `Default` in the Environment URLs table, else the first row.
- **`--screens=/a,/b`**: optional — skip the affected-screen scoping in Step 5 and test exactly these routes.

**`prod` and `production` are refused.** An unattended regression pass signs in and clicks through live member data. Say so and stop.

## Step 1: Fetch the Work Item

Read the work item from Azure DevOps using the project from the current repo's CLAUDE.md configuration. Expand with `relations` so PR links are included.

If the work item is not found, report the error and stop.

Capture: id, title, type, state, and any linked Pull Request artifacts. Then extract the requirements **by type** — the field differs and getting this wrong silently produces an empty test plan:

- **User Story / Feature** → `Microsoft.VSTS.Common.AcceptanceCriteria`.
- **Bug / Hot Fix** → `Microsoft.VSTS.TCM.ReproSteps`. Neither type has an acceptance criteria field.

Treat all of these as **empty**: `""`, whitespace, `<div></div>`, `<p><br></p>`, and the process-template placeholder `💡 Tip: Add "@serena rewrite" to Description for AI suggestions  Define acceptance criteria: - [ ]  - [ ]  - [ ]`. That last one is the trap — it is non-empty, so a length check says the opposite of the truth.

If the type's field is empty, fall back to `System.Description` and note `AC read from Description — misfiled` in the report. If both are empty, **continue anyway** and report `Acceptance criteria: none — regression sweep only`. The screen sweep is the point of `/qa`; it does not need acceptance criteria.

Download and view every embedded `<img>` in the description or criteria with WebFetch — mockups define the expected layout.

## Step 2: Resolve the Environment

Read the **Environment URLs** table from the current repo's `CLAUDE.md`:

```
| Branch | Environment | App URL | API URL |
|--------|------------|---------|---------|
| (none) | local | http://localhost:5173 | https://localhost:7001 |
| dev | Dev | https://dev.myapp.example.com | https://dev.api.myapp.example.com |
| test | Test | https://test.myapp.example.com | https://test.api.myapp.example.com |
```

Capture the target row's App URL and API URL, the `**Sign-in:**` descriptor, the test-account table, and — for the differential re-check in Step 7 — the **App URL of the row immediately below the target**. That row serves the pre-change build, which is what lets a failure be attributed rather than guessed at.

If the section is missing, or the target environment has no row, report:

```
AB#{id}: {title}

This project has no `## Environment URLs` section in CLAUDE.md, so I don't know where
the {environment} app is hosted. /qa cannot run.

Add this to CLAUDE.md — **above the `## Claude Kit Workflow` heading**, because
everything below that heading is replaced on the next kit update:

## Environment URLs

| Branch | Environment | App URL | API URL |
|--------|------------|---------|---------|
| dev | Dev | https://… | {inferred, or …} |
| test | Test | https://… | {inferred, or …} |

**Sign-in:** form at `/login`. Signed-in landing: `/dashboard`.

**Test accounts** — values live in environment variables; never write a password here.

| Role | Username variable | Password variable | Default |
|------|-------------------|-------------------|---------|
| Admin | `{PROJECT}_QA_ADMIN_USERNAME` | `{PROJECT}_QA_ADMIN_PASSWORD` | yes |

Want me to draft it with the API URLs filled in from your .env files? (yes / no)
```

The API URLs can be inferred from the client's per-environment env files (`Client/.env.development`, `.env.testing`, …), which already carry the API base URL. Grep for the single base-URL key and echo **only that value** — never print the contents of those files.

For `dev`, `test`, and `staging` also read the **Pipeline Configuration** table; the two tables are joined on the branch column, and a mismatch is a configuration error worth reporting. If Pipeline Configuration is missing, report that the project has no pipeline configuration in `CLAUDE.md` and stop.

## Step 3: Gate — Is a Browser Available?

Two checks, both required:

1. `.mcp.json` contains a `playwright` server. It is opt-in at install time, so a project that unchecked it has no browser.
2. `mcp__playwright__browser_navigate` is present in this session's tools. The server can be configured and still have failed to start.

```
AB#{id}: {title}

Playwright MCP isn't {configured for this project | connected in this session},
so I can't open a browser. /qa cannot run.

{To add it:  npx @chris1807/claude-kit init . --all --db=<your-db>  and check
 "Playwright (browser testing)", then restart the session.}
{It's in .mcp.json but didn't connect. Restart the session; if it still fails, the
 browser binaries may be missing — npx playwright install chromium}
```

## Step 4: Gate — Credentials and Sign-in Method

Resolve the role: `--role=<x>`, else the row marked `Default`, else the first row. Then check **presence only**. Never read a credential value in this step — the agent does that, inside its own transcript:

```bash
for v in {PROJECT}_QA_ADMIN_USERNAME {PROJECT}_QA_ADMIN_PASSWORD; do
  [ -n "${!v}" ] && echo "$v SET" || echo "$v MISSING"
done
```

Any `MISSING`:

```
AB#{id}: {title}

Missing test-account credentials for the {role} role:
  - {PROJECT}_QA_ADMIN_PASSWORD

/qa signs in unattended, so these must be exported before it can run:

  export {PROJECT}_QA_ADMIN_USERNAME="qa-admin@example.com"
  export {PROJECT}_QA_ADMIN_PASSWORD="…"

Use a throwaway QA account with least privilege, never a personal login. Never put
the password in CLAUDE.md, .env, or any file in the repo.
```

If the `**Sign-in:**` descriptor says the app uses SSO or Entra ID with MFA, stop here:

```
{environment} sign-in goes through {provider} with MFA, which can't be completed
unattended. /qa can't test this project until a cloud-only, MFA-exempt QA account
exists — or run the checks by hand against {app-url}.
```

## Step 5: Gate — Is the Code Actually There?

### For `dev`, `test`, `staging`

Being merged is not being deployed. Two separate facts, both required.

**5a. Every commit is on the branch.** Same method as `/where`:

1. `git fetch origin <target-branch>` and `git fetch origin <baseline-branch>`.
2. Find the item's commits three ways and dedupe by SHA: linked PRs → `lastMergeCommit`; `git log --all --grep="AB#<id>\b" --grep="#<id>\b" -i --format=%H`; branch names matching `*AB#<id>-*`.
3. For each commit: `git merge-base --is-ancestor <commit> origin/<target-branch>`.

**`/qa` requires all of them.** A partial match is the cherry-pick case `/where` reports as `1 of 2`, and testing half a story produces failures that are really missing code — a FAIL comment that blames a developer for a deployment mistake:

```
AB#{id}: {title}

Not fully deployed to {environment} — 1 of 2 commits present.

Present on origin/{branch}:
  a1b2c3d  AB#{id}: add export button
Missing:
  e4f5g6h  AB#{id}: fix CSV encoding

This is a partial cherry-pick. Get the rest onto {branch} (`/promote` or
`/cherry-pick AB#{id} {environment}`), then re-run. `/where AB#{id}` shows the
full picture.
```

No commits at all → `No commits found referencing this work item — nothing to test.` and stop.

**5b. The pipeline that deployed them is green.** Same method as `/promote`:

1. Take the merge time of the item's newest commit on the target branch.
2. Look up the branch's pipeline ID(s) in Pipeline Configuration. Poll `pipelines_build` for runs on `refs/heads/<target-branch>` **queued at or after that time**, matching the merge commit where the run exposes it, and **capture each run's id**. A run that completed before the merge is not this deployment — never take "the latest run on the branch".
3. Every pipeline on the branch (API **and** client) must be `succeeded`.
4. **Never block on a foreground `sleep`.** If a run is still going, watch its **run id** with `Monitor` or Bash `run_in_background`, and match failures as well as success.

| Result | Action |
|---|---|
| all `succeeded` | Proceed. Record `{pipeline} run {id}` for the report. |
| `inProgress` | `The {environment} deployment is still running ({pipeline} run {id}). I'm watching it and will start testing when it's green. Say \`stop\` to cancel.` |
| `partiallySucceeded` | `Not green — {stage} failed in run {id}. Test anyway? (proceed / hold)` and record it in the report. |
| `failed` / `canceled` | Stop. `The {environment} deployment failed — run {id}, stage {stage}: {log link}. The app may not contain AB#{id} at all.` |
| no run after the merge | Stop. `The commits are on {branch} but no CD run was queued after the merge. Nothing deployed AB#{id}.` |

### For `local`

No commit or pipeline gate — you are testing the working tree. Instead, probe the local App URL. If nothing answers:

```
Nothing is listening on {local-url}.

/qa doesn't manage dev servers — start the app first:
  {the project's start commands, e.g. `dotnet run --project src/API` and `npm run dev`}

Then re-run /qa AB#{id} local.
```

Also check whether the working tree actually contains the item's commits (`git log --grep="AB#<id>"` on `HEAD`). If not, warn but continue — the user may be mid-implementation, which is a legitimate reason to run `/qa local`.

## Step 6: Scope the Affected Screens, Then Get Approval

Skip to the approval block if `--screens=` was given.

1. **Changed files** — union of `git show --name-only --format= <sha>` over the item's commits, cross-checked against the linked PR's iteration changes. If they disagree, prefer the union and note it.
2. **Partition** into frontend (`*.tsx`, `*.ts`, `*.css`, `*.scss` under the client project found via `Glob("**/package.json")`), backend (`*.cs`), and other.
3. **Find the router** — `Glob("**/src/routes/**", "**/src/{App,Routes,router}.{tsx,ts}")`, then grep for `<Route`, `createBrowserRouter`, `path:`, `lazy(` to build a `{path → component file}` map.
4. **Reverse-import walk, max 4 hops.** For each changed frontend file, grep the client `src/` for importers of its basename or path, and walk upward until you reach a file that is a router element. The union of reached routes is the candidate screen list. Keep the hop chain — it is the evidence for *why* a screen is in scope.
5. **Backend endpoints → screens.** For each changed `*.cs` controller, read its route attributes (`[HttpGet("…")]`, `[Route("…")]`) to get endpoint paths, grep the client for each path to find the calling component, and feed those components back into step 4. This is what catches a backend-only story that still has a UI surface.
6. **Name matching** — match nouns from the title and criteria against route paths and nav labels. Union in.
7. **Confidence:**
   - 1–6 routes reached by a clean import chain → proceed, and list them.
   - More than 6 → present them all, test the 6 with the most changed files, say plainly that you are capping, and mention `--screens=`.
   - **0 routes → stop and ask.** Never silently test nothing:
     ```
     I couldn't map the changed files to any screen. Changed: {n} frontend, {m} backend files.
     {reason: no router found | only shared utilities changed | backend-only, no client caller found}

     Which screens should I test?   /qa AB#{id} --screens=/payments,/invoices
     ```

Known blind spots, worth saying out loud in the report when they apply: computed `import()`, barrel-file re-exports that flatten the graph, and theme, design-token, or i18n changes that touch every screen. For a genuinely global change, say so and cap at the 4 highest-traffic routes rather than claiming to be exhaustive.

Then present the plan and **wait**:

```
## QA plan — AB#{id} on {environment}

Work item: {title} ({type}, {state})
Target: {environment} — {app-url}
Role: {role} ({USERNAME_VAR})
Build: {n} of {n} commits on `{branch}`, {pipeline} run {id} green
Baseline for attributing failures: {baseline-env} — {baseline-url}

Screens the story touched:
| Screen | Route | Why |
|--------|-------|-----|
| Payment History | /payments/history | PaymentHistory.tsx changed |
| Export dialog | /payments/history | new component |
| Payment detail | /payments/:id | calls the changed endpoint |

Full regression of these {n} screens — every control, not just the new behaviour —
plus {m} acceptance criteria, console errors, and failed network calls.

This will create test data on {environment}, prefixed `QA AB#{id}`.

Open the browser and run it? (yes / edit the screen list / cancel)
```

## Step 7: Run It, Then Attribute Every Failure

Delegate to the **qa** agent with a brief containing: the work item id, title, type and state; the target App and API URLs; the baseline App URL; the sign-in descriptor; the **names** of the credential variables (never the values — say "they are set, read them yourself, never echo them"); the ordered screen list with each screen's changed files; and the criteria. Above 3 screens, invoke it once per batch so a long sweep can't exhaust its context mid-run.

When the report comes back, sort every failure using three filters, in order:

1. **Blame filter** — if the failing surface is not in the story's changed-file set and no changed file reaches it in the import walk, it is **pre-existing**. State the reasoning.
2. **Differential result** — the agent re-ran failing steps against the baseline environment, which serves the pre-change build. Fails on both → **pre-existing**; passes on the baseline → **regression introduced by this story**, which is the strongest evidence a FAIL can carry. Caveat that seed-data and config drift between environments can confound this.
3. **Flake filter** — the agent retried once. A pass on retry is `FLAKY`, not a failure.

Only filter 1's output can drive a `FAIL` verdict. A run that finds nothing but pre-existing issues is `PASS WITH FINDINGS` — do not let old bugs turn into this story's failure.

## Step 8: Report

```
QA — AB#{id}: {title}
{type} · {state} · {environment} — {app-url}
Build: {pipeline} run {id} · succeeded · commit {sha7}
Signed in as: {role} (from {USERNAME_VAR}) — value not shown
Screens tested: {n} · {route list}

## Acceptance Criteria
| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | {criterion} | PASS | {route} — {observation} |
| 2 | {criterion} | FAIL | see R1 |
| 3 | {criterion} | NOT TESTABLE | {reason} |

## Screen Regression — {route}
| # | Test | Steps | Expected Result | Result |
|---|------|-------|-----------------|--------|
| 1 | Route loads | Navigate to {route} | Renders, no error boundary | PASS |

## Regressions (attributable to AB#{id}) — {n}
### R1 — {short title}
- Screen: {route}
- Steps: 1. … 2. … 3. …
- Expected: {x}. Actual: {y}
- Evidence: console `{line}` | network `POST /api/x → 500`
- Differential: passes on {baseline-env} — introduced by this story
- Screenshot: {local path} — local only, not attached to the work item

## Pre-existing issues (found, not caused by AB#{id}) — {n}
- {route} — {issue}. Also fails on {baseline-env}. Recommend a separate Bug.

## Not testable — {n}
- {check} — {why}

## Test data created on {environment}
- {entity} "QA AB#{id} — …" (id {x}) — left in place for review

Verdict: PASS | PASS WITH FINDINGS | FAIL | INCOMPLETE
Work item state unchanged — `Ready for Staging` is yours to set.
```

## Step 9: Comment on the Work Item

Draft the comment, preview it, and **wait**. Before drafting, check the item's existing comments for a prior `/qa` result on the same commit SHA — three runs should not leave three near-identical comments. If one exists: `A /qa comment already exists for commit {sha7} ({date}). Post an updated one anyway? (yes / skip)`.

> **Why this comment is not the redundant kind.** `/rework` deliberately posts no summary comment, because the commits and the diff are already the record of what changed. A QA result duplicates nothing: it is the outcome of *executing* the software at a specific build in a specific environment, which exists in no diff, no PR, and no pipeline log. It is precisely the evidence the person who later sets `Ready for Staging` needs. Don't delete this step by applying the `/rework` rule uniformly.

The body, as HTML (Azure DevOps renders HTML in comments):

```html
<b>Automated QA — {verdict}</b> · {environment} · {date}<br>
Build: {pipeline} run {id} ({result}) · commit {sha7}<br>
Screens tested: {route list}<br>
Signed in as: {role} test account<br><br>

<b>Acceptance criteria — {x} of {y} pass</b>
<ul>
  <li>✅ {criterion}</li>
  <li>❌ {criterion} — {one-line reason}</li>
  <li>➖ {criterion} — not testable: {reason}</li>
</ul>

<b>Regressions introduced by this story ({n})</b>
<ol>
  <li><b>{title}</b> — {route}. Steps: {1-2-3}. Expected {x}, got {y}.
      Passes on {baseline-env}, so it came in with this story.</li>
</ol>

<b>Pre-existing issues found ({n})</b> — not caused by this story; also fail on {baseline-env}.
<ul><li>{route} — {issue}. Separate Bug recommended.</li></ul>

<b>Test data created on {environment}</b>
<ul><li>{entity} "QA AB#{id} — …"</li></ul>

<hr>
<i>Posted by <code>/qa</code>. Work item state unchanged — <b>Ready for Staging</b> remains
a human QA gate. No screenshots and no field values are attached, per the sensitive-data
policy.</i>
```

A `PASS` collapses to the header, the criteria list, the test-data list, and the footer.

Then:

```
QA drafted — nothing has been posted to AB#{id} yet.

## Work item comment
{the full body as it will appear}

Reply with one of:
- "approve" → post the comment exactly as shown
- "skip"    → post nothing (the report above is yours to keep)
- "edit <section>: <new text>" → revise, then I'll re-preview before posting

Wait for my response. Never post to the work item until I reply "approve".
```

On `approve`, post exactly one comment via `mcp__azure-devops__wit_work_item_comment_write`.

That's it. `/qa` never changes the work item's state — not `Ready for Testing`, not `Ready for Staging`, not anything. `Ready for Staging` is the human QA gate and no command in this kit sets it. `/qa` also never merges, pushes, creates a PR, triggers a pipeline, edits code, attaches a screenshot to the work item, or transcribes a field value from a screen. It reads, it clicks, it reports.

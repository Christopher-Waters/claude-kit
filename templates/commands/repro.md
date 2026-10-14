Reproduce a bug in a real browser — before a fix, to confirm it and pin it down, or after one, to prove it's gone. Usage: `/repro <work-item-id> [environment] [--verify | --reproduce] [--role=<role>] [--as=<persona-or-user>] [--as-role=<role>] [--attempts=<n>]`

Parse `$ARGUMENTS` to extract the work item ID. Accept formats like `AB#1234`, `#1234`, or just `1234`. If no ID is provided, report the error and stop.

- **Environment**: optional — `local`, `dev`, `test`, or `staging`. Defaults to `dev`.
- **`--verify` / `--reproduce`**: optional — force the mode. Without either, Step 3 picks it from where the fix is.
- **`--role`, `--as`, `--as-role`**: exactly as in `/qa`. `--as` is how you reproduce a bug **as the user who reported it**, on an app that supports impersonation.
- **`--attempts=<n>`**: optional — how many times to run the steps, 1–5. Defaults to 2, or 5 when an earlier `/repro` called the bug intermittent.

**`prod` and `production` are refused**, for the same reason as `/qa`: an unattended run signs in and clicks through live member data. Say so and stop.

`/repro` and `/qa` share one browser agent (**qa**) and one set of gates. `/qa` asks *"does this story work, and did it break anything?"* `/repro` asks a narrower question: *"does this bug happen?"* It asks it twice — once before the fix, so the developer starts from a confirmed reproduction, and once after, so "fixed" means something.

## Step 1: Fetch the Bug

Read the work item from Azure DevOps using the project from the current repo's CLAUDE.md configuration. Expand with `relations` so PR links are included. Not found → report the error and stop.

**Type gate.** Only a **Bug** or **Hot Fix** has repro steps. For any other type, stop:

```
AB#{id} is a {type}, which has no repro steps. /repro follows a bug's steps.
To test a story's acceptance criteria, run /qa AB#{id} {environment}.
```

Capture: id, title, type, state, created by, linked Pull Request artifacts, and these fields:

- `Microsoft.VSTS.TCM.ReproSteps` — the steps, usually followed by *actual* and *expected* results.
- `Microsoft.VSTS.TCM.SystemInfo` — browser, environment, and account notes, when filled in.
- `System.Description` — the fallback.

Apply `/qa` Step 1's empty-field rules. `""`, whitespace, `<div></div>`, `<p><br></p>` and the `💡 Tip:` placeholder are all empty. Repro Steps empty → use the Description, and note `Repro steps read from Description`. Both empty → stop:

```
AB#{id} has no repro steps, so there's nothing to follow.

Add them to the work item's Repro Steps and re-run — or give them to me here and I'll
use them for this run only (they won't be written back to the work item).
```

**Read the comments.** Look for two things:

1. **Earlier `/repro` results.** They start with `Automated repro —`. Record each one's mode, verdict, environment, commit, and date. A prior `REPRODUCED` can serve as the control in Step 3, and a prior `INTERMITTENT` raises the default attempts to 5.
2. **Detail the steps leave out.** Which user hit it, which record, which environment, which browser. A named user feeds the `--as` suggestion in Step 4.

Download and view every embedded `<img>` in the steps, description, and comments with WebFetch. A screenshot of the bug is often the clearest statement of its signature.

## Step 2: Environment, Browser, Sign-in

Read `.claude/commands/qa.md` and run its **Step 2** (Resolve the Environment), **Step 3** (Is a Browser Available?) and **Step 4** (Sign-in Method, Credentials, Impersonation) exactly as written. In their messages, say `/repro` where they say `/qa`. Every stop condition in those steps stops `/repro` too. One refinement applies: under an ad-hoc `--as`, `/qa` makes the whole run read-only, but `/repro` lets the user approve individual writing steps in Step 4.

## Step 3: Pick the Mode

Find the fix's commits the way `/qa` Step 5a does: linked PRs → `lastMergeCommit`; `git log --all --grep="AB#<id>\b" --grep="#<id>\b" -i --format=%H`; and branches matching `*AB#<id>-*`. Dedupe by SHA. Then check each commit against the target with `git merge-base --is-ancestor <sha> origin/<target-branch>`, or against `HEAD` for `local`.

| Fix commits | On the target | Mode |
|---|---|---|
| none | — | **reproduce** — no fix exists yet |
| some | not all | **reproduce** — the fix exists but isn't fully on {environment}, so this run confirms the bug on the old build |
| some | all | **verify-fix** |

For `local`, also count it as verify-fix when the current branch matches `*AB#<id>-*` and the working tree has uncommitted changes — that is a fix in progress. Remind the user that the running dev server must be serving this working tree.

**Overrides.** `--reproduce` always wins. `--verify` on a target that lacks some fix commits is refused: verifying a fix that isn't deployed only tests the old build.

```
The fix for AB#{id} isn't fully on {environment} — {x} of {y} commits present.
/repro --verify here would test the build without it.

Run /repro AB#{id} {environment} to confirm the bug on this build, or verify where the
fix is: {environments whose branch has every commit, or "nowhere yet"}.
```

**Verify-fix on `dev` / `test` / `staging`** → also run `/qa` **Step 5b**. The pipeline that deployed the fix must be green. Being merged is not being deployed. **`local`, either mode** → run `/qa` Step 5's `local` probe. Reproduce mode on a deployed environment needs no pipeline gate, because it tests whatever is there.

**Pick the control** — verify-fix only. The control is what tells *fixed* apart from *these steps never triggered it*. Take the first one of these that applies:

1. A prior `/repro` comment recorded `REPRODUCED` with the same steps, on a commit without the fix → it is the control. No control run is needed.
2. Otherwise, walk down the `## Environment URLs` rows below the target, and take the first one whose branch lacks at least one fix commit. That environment still serves the bug. Under `--as`, it must also offer impersonation; skip any row that doesn't.
3. Neither → no control. Step 6 can then only say `FIXED — UNCONFIRMED`, and the plan says so up front.

## Step 4: Turn the Report Into a Script, Then Get Approval

Rewrite the repro steps as a numbered script the agent can follow literally: a route, a control's visible label, the value to enter. Keep the report's own wording where it is already concrete. Resolve "go to the bills page" to the route. When a step names something vaguely, like *"a bill"* or *"any provider"*, keep it vague and let the agent pick a suitable record. Never invent a record id.

Then define the two things the agent checks for. Without them a run proves nothing:

- **Bug signature** — the *actual result*, made observable: a status code, a message, a wrong value, a console error, a control stuck in the wrong state.
- **Expected behaviour** — the *expected result*: what a correct build shows at the same point.

If the report doesn't say what the bug looks like, ask one question and wait: `What do you see when the bug happens? I need something observable — an error message, a wrong value, a failed request.`

Mark every step that writes:

- `← writes: {what}` — submits, saves, approves, or sends. It runs under the normal write rules: prefixed QA data, and nothing that emails a real person.
- `← manual only — destructive` — it breaks one of the agent's write-safety rules: payment, settlement, bulk action, tax document, export-all, or a delete. The agent records it as `STEP FAILED`. If the bug sits behind such a step, say plainly that `/repro` can't reach it.
- `← manual only — protected input` — it requires typing an SSN, TIN, bank account number, or another protected value. The agent never types one.
- **Under an ad-hoc `--as`,** every writing step needs explicit approval here. Everything done while impersonating is recorded as that user. Approved steps go to the agent as **approved mutating steps**; the rest become `STEP FAILED — would write as {target}`.

**Suggest impersonation when it fits.** Step 1 may have found a named user who hit the bug. If the project's `**Impersonation:**` block covers this environment and `--as` wasn't given, add `Tip: the report says this happens to {user} — re-run with --as="{user}" to reproduce it as them.` If the bug is about what a *role* sees, suggest the matching persona.

Present the plan and **wait**:

```
## Repro plan — AB#{id} on {environment}

Bug: {title} ({type}, {state})
Mode: {reproduce — no fix exists yet
       | reproduce — fix is on {branch} but not on {environment}
       | verify-fix — {n} of {n} fix commits on `{branch}`, {pipeline} run {id} green}
Target: {environment} — {app-url}
Sign-in: {role} ({method})
Impersonating: {persona} ({role}) | {search term} — ad-hoc user, read-only except approved steps | none
Control: {baseline-env} — {url}, which doesn't have the fix
        | prior /repro on {date} reproduced it on {env} at {sha7}
        | none — {reason}; a pass can only be FIXED — UNCONFIRMED
Attempts: {n}

Steps:
1. Go to /bills
2. Open a bill in "Pending" status
3. Click "Convert to Check"
4. Click "Confirm" in the dialog          ← writes: converts the bill
5. Open the Payments tab

Bug signature: POST /api/bills/{ref}/convert → 500, and the error toast "Something went wrong"
Expected behaviour: the bill shows status "Check Issued" and a payment row appears

{Tip: …}

Run it? (yes / edit the steps / edit the signature / cancel)
```

## Step 5: Run It

If `/qa` Step 4 chose a hand-off, for either method, run `/qa` **Step 7a** (the sign-in hand-off) first.

Delegate to the **qa** agent with a brief containing:

- the task (`reproduce` or `verify-fix`), plus the bug's id, title, type and state;
- the target App and API URLs;
- the control's App URL, if the control is an environment, with "run a control" — otherwise `none`;
- the sign-in method and descriptor, with `session handed over` or `unattended`;
- the **names** of the credential variables, never the values;
- the impersonation block and target, marked persona or ad-hoc, if `--as` was given;
- the approved script, the bug signature, the expected behaviour, the approved mutating steps, and the number of attempts.

If the agent returns `BLOCKED — session ended`, run `/qa` Step 7a once more and re-invoke it for the attempts it didn't reach. After a handed-over session, close the browser yourself at the end.

**Under a `form` hand-off there is no control run on another environment.** The agent can't sign in there. Step 3's control then falls back to a prior `/repro` comment or none, and the plan must say so.

## Step 6: Verdict

Assign the verdict from the agent's attempts and the control. Count a `STEP FAILED` at or before the signature step as **not run**, never as *not seen*.

### Reproduce mode

| Attempts | Verdict |
|---|---|
| Signature seen in every attempt | `REPRODUCED` |
| Seen in some attempts | `REPRODUCED — INTERMITTENT ({k} of {n})` |
| Seen only under a variation | `REPRODUCED — under V{n}: {what changed}`. The report's steps are incomplete; recommend updating them |
| Not seen, expected behaviour observed | `NOT REPRODUCED` |
| Not seen, something else went wrong | `NOT REPRODUCED — DIFFERENT SYMPTOM: {what}` |
| A step couldn't be performed | `BLOCKED — {reason}` |

### Verify-fix mode

| Target | Control | Verdict |
|---|---|---|
| Not seen in any attempt, expected behaviour observed, screen check clean | seen, or a prior `REPRODUCED` | `FIXED` |
| Same | not seen, or no control | `FIXED — UNCONFIRMED` — the steps didn't trigger the bug on the old build either, so this run can't tell fixed from never-triggered |
| Not seen, expected behaviour observed, screen check fails | any | `FIXED — SCREEN REGRESSION: {check}`. Attribute it the way `/qa` Step 7 does: does the failing surface touch the fix's changed files? |
| Not seen, but expected behaviour **not** observed | any | `NOT FIXED — DIFFERENT SYMPTOM: {what happened instead}` |
| Seen in any attempt | any | `STILL REPRODUCES ({k} of {n})` |
| A step couldn't be performed | any | `BLOCKED — {reason}` |

A verify-fix with fewer than 3 attempts on a bug a prior run called intermittent can only be `FIXED — UNCONFIRMED`. Two clean runs of a 1-in-3 bug is just luck.

## Step 7: Where to Look — whenever the signature was seen

The developer's next question is *where*. Answer it from the evidence, reading only:

1. **Failing request → handler.** For each failing `METHOD path → status` the agent recorded, grep the API's controllers for the route attributes (`[Route]`, `[HttpPost("…")]`) that match. Report the action by `file:line`.
2. **Screen → component.** Map the route where the signature appeared to its component through the client router, as `/qa` Step 6.3 does. Then look one hop down to the components that make the failing call.
3. **Console error → source.** If the first console line names a function or a component, grep for it.

Report at most 5 locations, each with the evidence that led there. **Never claim a root cause** — these are places to start reading.

In **verify-fix** mode, when the bug still reproduces, run the same mapping. Then compare the locations with the fix commits' changed files. `the fix changed BillService.cs, but the failing call is handled in BillsController.cs:212` is the most useful sentence this command can produce.

## Step 8: Report

```
Repro — AB#{id}: {title}
{type} · {state} · {environment} — {app-url}
Mode: {reproduce | verify-fix} · Build: {pipeline run {id}, commit {sha7} | local working tree}
Signed in as: {role} ({method}) — value not shown
Impersonating: {persona | search term} as {role} | none

Verdict: {verdict}

## Attempts
| Attempt | Variation | Result | At step | Evidence |
|---------|-----------|--------|---------|----------|
| 1 | — | SIGNATURE SEEN | 4 | network `POST /api/bills/…/convert → 500` |
| 2 | — | SIGNATURE SEEN | 4 | network `POST /api/bills/…/convert → 500` |

## Control — {baseline-env | prior run {date}}
{SIGNATURE SEEN at step n | NOT SEEN | not run — {reason}}

## Screen check — {route}          ← verify-fix only
{rows 1–5 from the agent}

## Where to look                   ← when the bug reproduced
1. `{file}:{line}` — {why: handles POST /api/bills/{ref}/convert, which returned 500}
2. …

## Not testable
- {step or check} — {why}

## Test data created on {environment}
- {entity} "QA AB#{id} — …" (id {x}) — left in place for review

Screenshot: {local path} — local only, not attached to the work item

Next: {REPRODUCED → `/implement AB#{id}`
       | NOT REPRODUCED → ask the reporter for the record, the user, and the environment
         where it happened; or re-run with --as or in another environment
       | FIXED → `Ready for Testing` / `Ready for Staging` is yours to set
       | FIXED — UNCONFIRMED → reproduce it on the old build first: /repro AB#{id} {baseline-env} --reproduce
       | STILL REPRODUCES / NOT FIXED → `/rework AB#{id}`, with the "Where to look" list above}
```

## Step 9: Comment on the Work Item

Draft the comment, preview it, and **wait**, exactly as in `/qa` Step 9. Before drafting, check the existing comments for a `/repro` result with the **same mode and commit**. If one exists: `A /repro {mode} comment already exists for commit {sha7} ({date}). Post an updated one anyway? (yes / skip)`.

This comment matters more than `/qa`'s, because the next `/repro` reads it. A `REPRODUCED` here becomes the control that lets a later verify-fix say `FIXED` rather than `FIXED — UNCONFIRMED`. So **always include the script and the signature** — they are what make two runs comparable.

```html
<b>Automated repro — {verdict}</b> · {mode} · {environment} · {date}<br>
Build: {pipeline} run {id} · commit {sha7}{ | local working tree}<br>
Signed in as: {role} test account{, impersonating {persona | "the reporting user"}}<br><br>

<b>Steps run</b>
<ol>
  <li>{step}</li>
</ol>
<b>Bug signature:</b> {signature}<br>
<b>Expected:</b> {expected behaviour}<br><br>

<b>Result — signature seen in {k} of {n} attempts</b>
<ul>
  <li>Attempt 1: {result} at step {n} — {evidence}</li>
</ul>
{<b>Control</b> — {baseline-env}: {result}<br>}
{<b>Where to look</b><ul><li><code>{file}:{line}</code> — {why}</li></ul>}
{<b>Test data created</b><ul><li>{entity} "QA AB#{id} — …"</li></ul>}

<hr>
<i>Posted by <code>/repro</code>. Work item state unchanged. No screenshots and no field
values are attached, per the sensitive-data policy.</i>
```

The comment never names an ad-hoc impersonation target. It says *"the reporting user"*, because the search term is often a real person's email.

Then:

```
Repro drafted — nothing has been posted to AB#{id} yet.

## Work item comment
{the full body as it will appear}

Reply with one of:
- "approve" → post the comment exactly as shown
- "skip"    → post nothing (the report above is yours to keep)
- "edit <section>: <new text>" → revise, then I'll re-preview before posting

Wait for my response. Never post to the work item until I reply "approve".
```

On `approve`, post exactly one comment via `mcp__azure-devops__wit_work_item_comment_write`.

That's it. `/repro` never changes the work item's state — a `FIXED` doesn't move the bug forward, and a `NOT REPRODUCED` doesn't close it or tag it. Those are human calls. It also never merges, pushes, creates a PR, triggers a pipeline, edits code, attaches a screenshot to the work item, or transcribes a field value from a screen. It reads, it clicks, it reports.

Implement work item AB#$ARGUMENTS on autopilot: the full `/implement` workflow, start to PR, with no human approval gates. Claude makes every decision `/implement` would ask about, and records it. Follow this workflow:

## What autopilot changes, and what it doesn't

`/autopilot` runs **every step of `/implement`**: workspace, summary, exploration, plan, architect review, branch, `Active` state, child Task, implementation with unit tests, build, full test suite, lint, AC coverage, code review, UAT checklist, PR, deployment-script attachments, Task close, `Code Review` state, and worktree cleanup. Features run in `Custom.Order` waves, exactly as `/implement` runs them.

The only difference is who answers `/implement`'s prompts. Wherever `/implement` waits for the user, autopilot applies the matching rule in the **Gate Table**, writes the decision to the **Decision Log**, and keeps going. **Never call `AskUserQuestion`, and never end a turn to wait for a reply**, at any point in the run.

What stays fixed:

- **The PR is the human gate.** Autopilot opens the PR and stops there. It never merges, approves, or sets auto-complete on the PR, and it never promotes or deploys. Everything it decided is in the PR for the reviewer.
- **Removing the approver doesn't remove the scrutiny.** Each place `/implement` relies on a person to catch a mistake gets an independent check instead. See **Independent Checks**.
- **No human decision is taken.** Autopilot never moves an item past `Code Review`, never sets `Ready for Testing`, never changes a Feature's state, and never closes a story. Only Tasks are closed, as in `/implement`.
- **Every rule in CLAUDE.md and every hook still holds.** That covers sensitive fields, secrets, and protected files. When a hook blocks something, record it as an open item for the PR. Never route around it.

**Permission prompts are not this command's to remove.** Autopilot drops the prompts `/implement` asks. Claude Code's own permission prompts belong to the harness and the user's permission mode, and no command can suppress them. The work happens in a sibling worktree (`../{repo}-AB{id}`), outside the session's folder, so the first edit there prompts unless that folder was added with `/add-dir` or the session runs in auto mode.

## Arguments

`$ARGUMENTS` is the work item id, as `1234` or `AB#1234`. It can be followed by `work in place` or `no worktree`, the same opt-out `/implement` takes. Strip the phrase before reading the id.

## Before Step 0: Load `/implement`

Autopilot executes `/implement`'s steps, so read them first: `.claude/commands/implement.md` at the repo root (`git rev-parse --show-toplevel`). The file is committed, so every worktree has it. If it isn't there, fall back to `~/.claude/commands/implement.md`. If neither exists, Hard Stop: `/autopilot runs /implement's workflow, and .claude/commands/implement.md is missing. Re-run npx @chris1807/claude-kit init.`

Run implement.md from Step 0 through Step 11, or F1 through F8 for a Feature. **This file wins every conflict with implement.md.** Three overrides apply throughout:

1. **Gates resolve without asking.** Where implement.md says to wait, ask, or prompt, or offers a `(yes / no / …)` choice, apply that gate's row in the Gate Table. For a prompt the table doesn't list, take the answer implement.md suggests (its "suggested", "recommended", or "press enter to accept" value). If it suggests none, take the option that changes the least and is easiest to undo. Log the decision either way.
2. **Ultracode is off, always.** Autopilot never calls the `Workflow` tool, whatever the size of the change, and skips every Ultracode callout in implement.md. An unattended run multiplies cost the most, so it runs lean. implement.md's **Model Tiers** still apply: implementers run on Sonnet, and the main loop takes a piece over when one gets stuck.
3. **The run ends one of three ways:** a PR ready for review, a draft PR with open items (**Unfinished Work**), or a **Hard Stop**. There is no other outcome.

Open with this block, then start Step 0 without waiting:

```
## Autopilot — AB#{id}
Running /implement end to end with no approval gates. Every decision is logged and posted to the PR.
I stop only on a hard stop; the PR is where you review.
Claude Code's own permission prompts can still appear. Edits in the ticket's worktree (../{repo}-AB{id})
prompt once unless you've added it with /add-dir or are in auto mode.
```

## Gate Table

Each row is a prompt in implement.md and the decision autopilot makes instead. Log every row that fires.

| implement.md | The prompt | Autopilot's decision |
|---|---|---|
| **Workspace** | | |
| 0b | The folder is on another ticket's branch and CLAUDE.md names no PR target. Which base? | origin's default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`). |
| 0b | *(new check)* | **PR-target guard.** If CLAUDE.md names the PR target (e.g. "PRs always target `main`") and `CURRENT` is a different branch, use the named target, unless the item is a Hot Fix. Otherwise an unwatched run started on `dev` would open a PR that deploys on merge. |
| 0b | `origin/{BASE_BRANCH}` doesn't exist. | Hard Stop. |
| 0d case 3 | `WT` exists but git doesn't know it. Delete or rename it? | Leave the folder alone. Use the first free `{WT}-2`, `{WT}-3`, … as `WT`. |
| 0d case 4 | Several local `*/AB#{id}-*` branches. Which one? | The one with the newest commit (`git for-each-ref --sort=-committerdate`). |
| 0d | The worktree is already locked. | Hard Stop. Another session may be editing it, and two unwatched edit streams in one folder can't be untangled afterward. If the lock is stale: `git worktree unlock "{WT}"`. |
| **Work item and plan** | | |
| 2 | Summary: "Does this look correct? Any added context?" | Print the summary, with the effort recommendation as information only, and continue. Resolve gaps with the **Ambiguity Rule**. |
| 2 | Use Ultracode? | No (override 2). |
| 3 | Approve this plan? | Run the Architect Review (see **Independent Checks**), apply what it finds, print the final plan, and continue. The plan goes in the PR thread. |
| **Branch and Task** | | |
| 4 | The open Task has no estimate. Proposed hours OK? | Set the proposed hours on `OriginalEstimate` and `RemainingWork`. |
| 4 | More than one open Task. Which one? | The one in `Active`, then the one titled `{PREFIX} - Implement…`, then the lowest id. Leave the others alone and name them in the final report. |
| 4 | No open Task. Create it? (yes / edit / skip) | Yes, with the proposed title and hours. |
| 4 | Task create or link failed. Continue without one, or stop? | Continue. Step 10's after-the-fact rule creates the Task when the PR goes up. Log a warning. |
| 4 | The state can't be advanced (no `Active` or fallback). | Log it and continue. |
| **Quality** | | |
| 6, 7 | The build or test suite is red. | Fix it and re-run, up to the round limit in **Unfinished Work**. Check **Pre-existing Failures** first. |
| 7.3 | A missing environment-config cell. What value? | **Environment Config Rule**, below. |
| 7.4 | An AC has no covering test or code path. | Add the coverage. If the AC can't be verified automatically (visual layout, a third-party system), mark it **manual-only** on the UAT checklist and in Open Items. |
| 8 | Address the findings? (yes / select / skip) | Fix every verified must-fix. Fix a should-fix when it sits in code this change wrote or touched. List the remaining should-fixes and every nit in Open Items. Re-run the review after each round. |
| **PR** | | |
| 9 | UAT: "Did manual testing pass?" | Don't wait. The checklist goes in the PR description as unchecked boxes for the reviewer, and the PR says nobody has tested it by hand. |
| 9 | Hot Fix: Create PR? | Yes. |
| 10 | Close related Tasks? (yes / no / select) | Close only the Task this run logged against (Step 4). Leave other open Tasks alone and name them in the final report. |
| 10 | Completed hours? | The suggested value: `OriginalEstimate` when `CompletedWork` is empty. Keep `CompletedWork` when it's already set. |
| **Feature** | | |
| F1 | No implementable child stories. Implement the Feature itself? | Yes, through Steps 2–11, if the Feature's own description or AC describes buildable work. Otherwise Hard Stop. |
| F2 | Feature summary and wave plan. Look correct? | Print it and continue. Stories with no `Custom.Order` run in the final wave, in id order. |
| F4.1 | Approve this wave's plan? | Run the Architect Review on the combined wave plan, apply what it finds, and continue. |
| F4.2 | Create these Tasks? | Yes, for every story in the wave. |
| F6 | Combined UAT | As Step 9, grouped by story. |

## Ambiguity Rule

`/implement` closes a gap in the requirements by asking. Autopilot closes it with these rules, in order, and logs each one as an **assumption**:

1. **The latest word wins.** A later comment overrides an earlier one. Comments override the AC field, and the AC field overrides the description. An embedded mockup decides layout, and the text decides behavior.
2. **Follow the codebase.** Where the work item is silent, do what the nearest existing feature of the same kind does: the same validation style, the same paging, the same error shape.
3. **Take the smallest reading that meets the literal AC.** Never add behavior to fill a gap.
4. **Fail closed.** When it's unclear who may see or do something, take the more restrictive reading. A reviewer can widen access in one line, but nobody can un-expose data.

An assumption that changes what a user sees or can do also goes in Open Items, so the reviewer can't miss it.

## Independent Checks

Each human check in `/implement` gets a stand-in that doesn't share the author's reasoning:

| `/implement` relies on | Autopilot uses |
|---|---|
| The user reading the plan | The Architect Review in the main loop on **every** plan (implement.md's non-Ultracode variant). Answer each question from the code, not from the plan's own prose. Apply each finding unless it grows the scope or contradicts an AC. Log every finding you decline, with the reason. |
| The user choosing which review findings to fix | One `reviewer` agent (Sonnet) on the diff, launched with the `Agent` tool so it doesn't share the author's reasoning. Give it the work item, the AC, and the worktree path, but not the plan's justification. Before fixing a finding, check it against the code yourself and drop it if it doesn't hold; that check is what "verified" means below. Later rounds review only the diff the fixes introduced. |
| The user doing UAT | Every AC traced to a test or code path (Step 7.4), the full test suite including any E2E specs the repo has, and the UAT checklist handed to the reviewer in the PR. |

## Environment Config Rule (Step 7.3)

For each key this change added to one environment file but not to its parallels:

- **Same in every environment by nature** (a page size, a timeout, a retry count, a relative path): copy the base value into every parallel file that exists.
- **Varies by environment, or is a secret or a feature switch** (a URL, host, connection string, key, credential, or flag): don't invent a value. Leave the file as it is and list the cell under **Config to supply**.
- **`appsettings.Staging.json` and `appsettings.Production.json`**: never edit them, since the protected-files hook blocks both. Always list their cells under Config to supply.

## Pre-existing Failures

Step 7 treats any red test as a regression from this change. Before spending fix rounds on a failing test outside the change's files, check whether it also fails on the base. Run that test in a temporary detached worktree at `origin/{BASE_BRANCH}`, then remove the worktree. If it fails there too, it's pre-existing. Don't fix it here, because that's scope nobody asked for. List it in Open Items and carry on.

## Unfinished Work: the Draft PR

Autopilot gets **three fix rounds** at each of these: a red build, a red test suite (regressions only), and verified must-fix review findings. If a round limit runs out, or an AC can't be met without breaking a rule in CLAUDE.md, stop fixing and finish as a draft:

1. Commit what's there. Run lint, but don't hide what's still failing.
2. Push, and create the PR with `isDraft: true`. Put a **⚠ Autopilot could not finish** section at the top of the description: what's failing, what was tried, and where it stands.
3. Link the PR and attach deployment scripts as usual.
4. **Leave the work item in `Active` and the Task open.** Don't log hours and don't move anything to `Code Review`. The work isn't ready for review, and the board shouldn't say it is.
5. Run Step 11 as usual. The branch is on origin, and `/rework AB#{id}` picks it back up.

A draft keeps the work and puts the problem in front of a person. Stopping without a PR would leave both on a local disk nobody is watching.

## Hard Stops

Halt, report, and change nothing further. Every hard stop happens before any code is written:

- The Azure DevOps MCP server isn't connected, or the work item isn't found.
- The work item is `Closed`, `Removed`, or `Deployed`.
- The work item already has a linked PR that is **active or completed**. That is `/rework`'s job, so suggest `/rework AB#{id}`. An abandoned PR doesn't count.
- There's nothing to build. The description and the acceptance criteria (Repro Steps for a Bug or Hot Fix) are both empty. Treat the template placeholder (`💡 Tip: … Define acceptance criteria: - [ ] …`) as empty.
- implement.md is missing, `origin/{BASE_BRANCH}` is missing, or the ticket's worktree is locked (see the Gate Table).

If a hard stop hits after Step 0 made a new worktree, give it back: `git worktree unlock "{WT}"`, then `git worktree remove "{WT}"`. It has no branch or changes yet.

## Decision Log

Log one line for every decision a person would have made under `/implement`: each Gate Table row that fired, each assumption, each architect finding declined, and each review finding left unfixed.

`| {n} | {step} | {decision} | {why} |`

Write the log to a file as you go, `{scratchpad}/autopilot-AB{id}.md` (the system temp dir if the session has no scratchpad), not only to the conversation. A Feature run is long enough for the context to be summarized, and the log has to survive that intact. The PR thread is built from this file.

Print one progress line as each step finishes, so a user who comes back can see how the run went: `▶ Step 3 — plan: 4 files, 6 tests; architect review changed 2 things`.

## The PR (Step 10)

Create the PR as implement.md Step 10 says, with these additions:

- **Labels:** `autopilot`, plus `hotfix` for a Hot Fix.
- **Description.** Azure DevOps caps it at 4,000 characters, so keep it to this:

  ```
  > 🤖 Opened by /autopilot. No person approved the plan or ran UAT. The full plan,
  > architect review, and every decision are in the first comment thread.

  ## Summary
  {what changed, 3–6 bullets}

  ## Open Items
  {Config to supply (key × environment) · assumptions that change behavior · manual-only ACs ·
   should-fixes and nits not fixed · pre-existing failures · hand-run scripts. "None" if empty.}

  ## UAT Checklist
  - [ ] {item}
  ```
- **First comment thread.** Right after creating the PR, post one thread (`repo_pull_request_thread_write`) with the final plan, its Architect Review section, AC coverage as `| AC | Covered by |`, and the full Decision Log. Leave it active for the reviewer to resolve once they've read it.

## Final Report

When Step 11 is done, print:

```
## Autopilot finished — AB#{id}: {title}

PR #{n} → {BASE_BRANCH}   {ready for review | DRAFT — see ⚠ in the description}
Work item: {state}   Task AB#{t}: {closed, {h}h logged (the estimate; edit it if actual differs) | left open}
Decisions: {n} (in the PR thread)   Open items: {n}   Other open Tasks left alone: {ids, or omit}

Next: review the PR and run its UAT checklist. Once it's on Dev, run /qa AB#{id}.
```

For a hard stop, print the reason and what to fix.

Then, if a `PushNotification` tool is available (load it with `ToolSearch` if it's deferred), send one notification: `AB#{id}: autopilot opened PR #{n}`, `AB#{id}: autopilot opened draft PR #{n}, needs attention`, or `AB#{id}: autopilot stopped, {reason}`. The user has probably walked away, and this is how they find out.

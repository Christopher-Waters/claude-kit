# Roadmap — Autonomous Delivery Pipeline

> **Status: not scheduled.** This is a captured design, not a commitment. Nothing here is built. Recorded 2026-09-12 so the shape survives until it's worth building.

The goal: a work item moves from `Dev Ready` to `Ready to Deploy` with agents doing every mechanical step and humans only making judgment calls. Three new pieces — a serial `/implement-sprint`, an autonomous **devops** agent, and a **qa** agent that leaves reviewable evidence — plus one idea that ties them together.

## The organizing idea: the work item state *is* the queue

There is no scheduler to build. Each state is owned by exactly one actor, and machine states alternate with human states. An agent's job is: find items in a state I own, act, move them to the next state. That's the whole orchestration model.

| State | Owner | Action | → Next state |
|---|---|---|---|
| `Dev Ready` | `/implement-sprint` | implement, PR | `Code Review` |
| `Code Review` | **devops** | merge, deploy to Dev | *(stays — see note)* |
| `Code Review` (on Dev) | **qa** | browser test; post report + spec + screenshots | *(stays; posts pass/fail — never advances it)* |
| `Code Review` + qa pass | 👤 **developer** | read the QA report; re-run the spec if they want | `Ready for Testing` — **set by hand, never by an agent** |
| `Ready for Testing` | **devops** | promote to Test | `Testing` |
| `Testing` | 👤 **tester** | test on Test | `Ready for Staging` / ❌ back to dev via `/rework` |
| `Ready for Staging` | **devops** | promote to Staging | `Staging` |
| `Staging` | 👤 **PM** | verify the change is there | `Ready to Deploy` |
| `Ready to Deploy` | **devops** | promote to Prod | `Deployed` |
| `Deployed` | 👤 | verify in production | `Closed` |

Every human gate is a `Ready for …` state; every machine step sits between two of them. This is the rule already codified in kit 2.2.1 — `Ready for Testing` is a manual developer gate — and this pipeline is why that shape matters.

**No agent ever sets `Ready for Testing`.** A green QA run does not advance the item; it only produces the evidence. A developer reads that evidence and moves the state themselves. That single human decision is what separates "the agents think it works" from "a person has signed off," and it is the hinge the whole pipeline turns on. An agent that could set it would make every downstream gate decorative.

> **Note on `Code Review`:** deploying to Dev sets no state (2.2.1). So `Code Review` covers "merged, on Dev, being QA'd." If the implement→qa loop needs to be distinguishable from "just merged," that's an argument for an ADO tag (`qa-running`, `qa-passed`) rather than a new state — tags are cheap, states are a process-template change.

## Piece 1 — `/implement-sprint` (serial)

Query `@Me` + `@CurrentIteration`, state `Dev Ready`. Work the list **one item at a time**.

Serial, not parallel, and the reason is context: a full `/implement` run — work item, exploration, plan, architect pass, implementation, review, UAT — is a large amount of context, and N of them concurrently in one session compacts away the early ones. The [earlier parallel design](#parallel-later-not-first) is recorded below but is explicitly *not* the first version.

What it needs beyond today's `/implement`:
- A **queue view** up front: the items, their points, and the order, approved once.
- **Per-item gates stay** (the plan gate is the valuable one) but the summarize step collapses — you approved the queue already.
- **Resumability.** A sprint run will span sessions. State lives in the work items themselves, so re-running the command picks up where it left off — that falls out of the state machine for free.
- A **stop rule**: on the second consecutive item that fails build or review, stop and report rather than grinding through the sprint.

## Piece 2 — devops agent (autonomous promotion)

Today `templates/agents/project/deployer.md` commits, pushes, and triggers pipelines when asked. The new job is to act on its own when an item enters a state it owns.

Reuses the existing commands — `/promote`, `/deploy-release` — so this is orchestration, not new deployment logic.

**Decided: inline triggering, not polling.** Claude Code isn't a daemon, so something has to call it. The options were:
1. `/loop` or a scheduled routine polling ADO for items in machine-owned states. The `loop` and `schedule` skills already exist.
2. Triggered inline at the end of `/implement-sprint` and at the end of each qa run. No polling, but nothing moves while no session is open.
3. ADO service hooks → needs a listener this repo doesn't have. Out of scope.

**Start with (2).** Add (1) only if inline proves too passive in practice. A polling loop that finds nothing is pure cost, and (2) fails benignly: work sits until the next session rather than moving when it shouldn't.

**Decided: the Dev merge is not human-reviewed, on purpose.** Auto-merging to Dev means the PR lands without a person reading it. That's acceptable *for Dev specifically*, and only because two other things are true — `/implement` has already run its own code review (including the architect pass at plan time), and the promotion out of Dev is gated on a human who has read the QA report. This decision rests on those two, not on Dev being unimportant. If either stops holding, revisit it.

**Production stays gated.** `Ready to Deploy → Deployed` should keep a human confirmation even when everything upstream is automatic.

## Piece 3 — qa agent (browser test + reviewable evidence)

Test the acceptance criteria on Dev in a real browser, leave behind something a developer can act on, and either pass the item or hand findings back to the dev agent.

`templates/agents/global/qa.md` already does the testing half. The open question was what evidence it leaves.

### Not a recording

Video was the first idea and it is the wrong one. Two reasons, and the second is disqualifying.

**It's a poor fit for the decision being made.** The developer's question is "did it test the right things, and did they pass." That is a table. A video answers it in real time, can't be skimmed, searched, diffed, or reviewed in a PR, and is stale the moment the code changes.

**It bypasses every PII control in the kit.** All the sensitive-data guards are textual — hooks scanning Bash output, MCP results, and file writes. A video attached to a work item is a durable binary that no hook inspects, permanently viewable by anyone with work item access. One QA flow crossing a screen that renders a TIN or bank account puts that value in Azure DevOps with nothing in the way. There is also no video tool to build on: the Playwright MCP server exposes `browser_take_screenshot` and nothing else.

**Playwright trace files (`trace.zip`) are rejected for the same reason, harder.** A trace is genuinely more useful than video for debugging — scrub the actions, inspect the DOM at each step, read the network log. But it embeds full DOM snapshots, so it captures values that were in the DOM and never visible on screen. For PII that is strictly worse than video.

### What to leave instead

Three artifacts, in order of how much they matter:

**1. A structured QA report, as a work item comment.** The spine. One row per acceptance criterion: steps taken, expected, actual, verdict — plus console errors and failed network calls. It is text, so it is searchable, diffable, quotable in a PR, and *the kit's existing PII hooks can actually scan it.*

**2. The generated Playwright spec, committed to the repo.** The strongest of the three, and the real argument for dropping video. Rather than an artifact *of* the run, the test *as code*: the developer reads about thirty lines, or runs it themselves and watches it live — which is more convincing than watching a recording of someone else's run. It gets reviewed in the PR like any other code, every existing guard applies to it because it is just a file in the repo, and it stays behind as a regression test. The evidence and the test are the same object.

**3. Screenshots at decision points — deliberately chosen, masked.** Not a recording: a handful of stills at the end state of each AC, plus every failure. Playwright's `mask` option covers sensitive selectors. Bounded, reviewable, and each frame is a choice rather than a side effect.

This is a better answer to the original goal than video was. The developer ends up with something they can *act on* — read it, run it, review it — instead of something to watch, and the pipeline gains a regression test it would not otherwise have.

### Residual risk — still real, now bounded

Screenshots keep a slice of the PII problem, and it concentrates in the one place that isn't planned: **failure screenshots**. A failure is by definition where the agent didn't expect to be.

- An explicit **screen denylist** the qa agent will not navigate to.
- A denylisted screen is **never** captured, failure included — the failure gets reported in text instead.
- Verify `mask` behaves as expected before relying on it; don't assume.
- Test data only, never a production-shaped record.
- "This AC can't be tested without showing a sensitive field" is a **stop and ask**, not a problem to route around.

### Decided: generate specs, without widening the tool allowlist

`qa.md`'s security model is built on what it omits — no `browser_evaluate`, no `browser_run_code_unsafe` — because arbitrary page JS defeats every PII rule in the file. Generating a spec looks like it smuggles page JS back in.

It doesn't have to. **The agent's MCP allowlist stays exactly as it is.** The spec is written as a *file* and executed by Playwright through Bash. The qa agent never gains a tool that runs arbitrary JS against whatever happens to be on screen; it gains the ability to write code that is committed, diffed, and reviewed before it ever runs a second time.

That distinction is the entire decision — runtime `evaluate` is invisible and unreviewable, a committed spec is neither. If some future change proposes putting `browser_evaluate` back on the allowlist to make spec generation easier, **that** is the thing to refuse. Re-read `qa.md`'s sensitive-data rules before touching its `tools:` line. See `docs/agent-authoring.md`.

### The fix loop

qa fails → findings to the dev agent → fix → redeploy → re-test. Needs a **round cap** (2–3) before escalating to a human, or it ping-pongs indefinitely on something it can't fix.

## Decisions

Settled, with the reasoning, so a later session inherits conclusions instead of re-litigating them.

1. ~~`Testing` fail → `Dev Ready`?~~ **Run `/rework`, not `/implement`.** It fits better than expected — `/rework` ends by moving the item back to `Code Review` (`rework.md:381`), which is exactly this pipeline's re-entry point, so devops redeploys to Dev, qa re-tests, and the developer gate comes around again. It also already handles the case that matters here: a `Testing` failure happens after the PR merged, and Step 6 covers a completed PR by branching fresh from the target. No change needed to `/rework` itself.
2. **qa re-runs after every promotion, not only on Dev.** It got cheap the moment the evidence became a committed spec: later environments re-run the same test instead of producing new artifacts, so the marginal cost is a browser session rather than a new review surface. Treat it as a smoke test per hop — it catches environment-config drift, which is precisely the class of bug that only appears *after* a promotion.

3. **qa stays read-only; devops does every write.** Today `/qa` cannot change a work item's state because it holds no Azure DevOps write tools at all — the guarantee is structural, not a prose rule the model could talk itself out of. This pipeline creates real pressure to give qa write access so it can hand off directly. Resist it: qa posts a verdict, devops reads the verdict and moves the state. `docs/agent-authoring.md` covers why omission is the enforcement.

4. **One PR per work item.** A per-sprint PR would bundle unrelated changes into a single review and a single revert unit, which breaks `/rollback` and makes cherry-picking a subset impossible — and the kit's whole release model depends on both. The cost is real and accepted: a sprint produces N PRs, landing on a schedule the agents choose rather than when you're ready to read them. If that becomes the bottleneck, batch the *notification*, not the PRs.

## Suggested sequencing

Each step is independently useful, which matters because this may never be finished:

1. **`/implement-sprint`, serial, fully manual gates.** Valuable alone. No new agents.
2. **qa agent, report only** — automated AC testing on Dev, structured report as a work item comment. Text only: the whole value of the loop, none of the PII risk.
3. **Generated spec committed to the repo** — written as a file and run through Bash, with `qa.md`'s tool allowlist untouched.
4. **Masked screenshots**, once the denylist exists.
5. **devops agent**, triggered inline (option 2 above).
6. **Polling / scheduled devops**, if inline triggering proves too passive.

## Parallel, later, not first

The original sketch ran sprint items concurrently in git worktrees — the mechanism `/implement` already uses for Feature story waves (`templates/commands/implement.md:534`). Shelved for context-window reasons, kept here because the machinery exists and the reasoning may change:

- `git worktree add` per item, agents confined to their own directory, merge back in the main loop.
- Group items into waves by **file overlap** so concurrent agents don't collide on DI registration, routing, or migrations.
- Cap concurrency ~3–4; each worktree is its own install and build.
- Items with migrations, or touching auth or payments, run solo regardless.
- The gates have to batch (one plan, one approval per wave) or the human becomes the bottleneck and it's slower than serial.

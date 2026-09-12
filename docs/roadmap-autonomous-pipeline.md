# Roadmap — Autonomous Delivery Pipeline

> **Status: not scheduled.** This is a captured design, not a commitment. Nothing here is built. Recorded 2026-09-12 so the shape survives until it's worth building.

The goal: a work item moves from `Dev Ready` to `Ready to Deploy` with agents doing every mechanical step and humans only making judgment calls. Three new pieces — a serial `/implement-sprint`, an autonomous **devops** agent, and a recording **qa** agent — plus one idea that ties them together.

## The organizing idea: the work item state *is* the queue

There is no scheduler to build. Each state is owned by exactly one actor, and machine states alternate with human states. An agent's job is: find items in a state I own, act, move them to the next state. That's the whole orchestration model.

| State | Owner | Action | → Next state |
|---|---|---|---|
| `Dev Ready` | `/implement-sprint` | implement, PR | `Code Review` |
| `Code Review` | **devops** | merge, deploy to Dev | *(stays — see note)* |
| `Code Review` (on Dev) | **qa** | browser test, record, attach video | *(stays; posts pass/fail)* |
| `Code Review` + qa pass | 👤 **developer** | watch the video | `Ready for Testing` |
| `Ready for Testing` | **devops** | promote to Test | `Testing` |
| `Testing` | 👤 **tester** | test on Test | `Ready for Staging` / ❌ `Dev Ready` |
| `Ready for Staging` | **devops** | promote to Staging | `Staging` |
| `Staging` | 👤 **PM** | verify the change is there | `Ready to Deploy` |
| `Ready to Deploy` | **devops** | promote to Prod | `Deployed` |
| `Deployed` | 👤 | verify in production | `Closed` |

Every human gate is a `Ready for …` state; every machine step sits between two of them. This is the rule already codified in kit 2.2.1 — `Ready for Testing` is a manual developer gate — and this pipeline is why that shape matters: **the developer watching the QA video is the thing that sets `Ready for Testing`.** The state machine above only works because that transition is human-owned.

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

**Open: what wakes it up?** Claude Code isn't a daemon. Realistic options:
1. `/loop` or a scheduled routine polling ADO for items in machine-owned states. Simplest; the `loop` and `schedule` skills already exist.
2. Triggered inline at the end of `/implement-sprint` and at the end of each qa run. No polling, but nothing moves when no session is open.
3. ADO service hooks → needs a listener this repo doesn't have. Out of scope.

Start with (2), add (1) when it proves useful.

**Open: who reviews the PR?** Auto-merging to Dev means the PR lands without a human reading it. Probably acceptable *for Dev specifically*, given `/implement` already runs an automated code review and the promotion to Test is gated on a human. Worth being deliberate about rather than sliding into it.

**Production stays gated.** `Ready to Deploy → Deployed` should keep a human confirmation even when everything upstream is automatic.

## Piece 3 — qa agent (browser test + recording)

Test the acceptance criteria on Dev in a real browser, attach a **video** of the run to the work item, and either pass it or hand findings back to the dev agent.

`templates/agents/global/qa.md` already does the testing half. Two real gaps:

### Gap 1 — there is no video tool

The Playwright MCP server exposes `browser_take_screenshot` and no recording tool. Video is not available through the MCP path. Options:

| Approach | Gets video | Cost |
|---|---|---|
| Generate a Playwright **spec file**, run it with `recordVideo` | ✅ native | Departs from today's exploratory MCP-driven `/qa` |
| Screenshot per step, stitch to mp4/gif | ⚠️ approximation | No timing, no interaction feel |
| MCP for exploration, then generate a spec for the recorded run | ✅ | Two passes, more tokens |

**Leaning toward the generated spec.** It gets video for free *and* leaves behind a re-runnable regression test — which is worth more than the recording. The tradeoff is real though: `qa.md`'s security model is deliberately built on omitting `browser_evaluate` and `browser_run_code_unsafe`, and a generated script reintroduces arbitrary page JS by the back door. A generated-and-committed spec is reviewable in a way that runtime `evaluate` is not, but this needs a deliberate decision, not a shrug. See `docs/agent-authoring.md`.

Attachment itself is supported — `wit_work_item_attachment`. Watch ADO's attachment size cap; keep runs short and the resolution modest.

### Gap 2 — ⚠️ recordings bypass every PII control in the kit

This is the biggest risk in the whole plan and it should block the recording feature until answered.

Every sensitive-data guard in the kit is **textual** — hooks scan Bash output, MCP results, and file writes for field names. A video recording of the application is a durable binary artifact, attached permanently to a work item, that no hook can inspect. If a QA flow passes through a screen rendering a TIN, SSN, or bank account, that value is now in Azure DevOps, viewable by anyone with work item access, and the kit's controls never saw it.

Mitigations to design in from the start, not bolt on:
- An explicit **screen denylist** the qa agent will not navigate to.
- Playwright's `mask` option over sensitive selectors (works for screenshots; **verify it applies to video** — do not assume).
- Test data only — never a production-shaped record.
- Treat "this AC can't be tested without showing a sensitive field" as a **stop and ask**, not a problem to route around.

### The fix loop

qa fails → findings back to the dev agent → fix → redeploy → re-test. Needs a **round cap** (2–3) before escalating to a human, or it can ping-pong indefinitely on a finding it can't fix.

## Open questions

1. **`Testing` fail → `Dev Ready`?** That's the design as described, and it's clean. But it abandons the branch and PR, and re-running `/implement-sprint` creates new ones. `/rework` already handles "PR exists, feedback arrived" and is much cheaper. Decide: restart, or `/rework` on the existing branch?
2. **Does qa re-run after Test and Staging promotions,** or only on Dev? Re-running is cheap insurance; it's also more video.
3. **Where does `/qa`'s existing read-only guarantee go?** Today `/qa` provably cannot change state — it has no ADO write tools. This pipeline wants qa to hand off to devops. Keep qa stateless and let devops read its verdict, rather than giving qa write access.
4. **One PR per item, or per sprint?** Per item, almost certainly — but it means a sprint produces N PRs on a schedule set by the agents.

## Suggested sequencing

Each step is independently useful, which matters because this may never be finished:

1. **`/implement-sprint`, serial, fully manual gates.** Valuable alone. No new agents.
2. **qa agent without recording** — automated AC testing on Dev, findings as a work item comment. The whole value of the loop, none of the PII risk.
3. **Recording**, once Gap 2 has a real answer.
4. **devops agent**, triggered inline (option 2 above).
5. **Polling / scheduled devops**, if inline triggering proves too passive.

## Parallel, later, not first

The original sketch ran sprint items concurrently in git worktrees — the mechanism `/implement` already uses for Feature story waves (`templates/commands/implement.md:534`). Shelved for context-window reasons, kept here because the machinery exists and the reasoning may change:

- `git worktree add` per item, agents confined to their own directory, merge back in the main loop.
- Group items into waves by **file overlap** so concurrent agents don't collide on DI registration, routing, or migrations.
- Cap concurrency ~3–4; each worktree is its own install and build.
- Items with migrations, or touching auth or payments, run solo regardless.
- The gates have to batch (one plan, one approval per wave) or the human becomes the bottleneck and it's slower than serial.

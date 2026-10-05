Create a new Azure DevOps work item (Bug, User Story, Feature, or Hot Fix) interactively. Use this whenever the user asks to create, log, file, open, or raise a work item, ticket, bug, story, feature, or hot fix, whether or not they typed the command. Usage: `/create-work-item [description]`

This command walks the user through creating a Feature, Bug, User Story, or Hot Fix, develops an acceptance-criteria-ready plan, optionally embeds a UI mockup in the description, and creates the item in the chosen Azure DevOps project. For a Feature it can also draft and create the child User Stories that make the Feature implementable.

Treat `$ARGUMENTS` as an optional rough description that the user may have typed inline (e.g. `/create-work-item users should be able to export payments`). If provided, skip the initial "describe your requirements" prompt in Step 2 and use it as the starting requirements text — but still confirm with the user before proceeding.

**This command is the only way Claude creates a Feature, Bug, User Story, or Hot Fix.** A plain-language request ("log a bug that the export button 500s", "make a story for bulk assign") runs this command even when the user didn't type it. Claude invokes it through the Skill tool with the request text as `$ARGUMENTS`, and the `work-item-intent.sh` hook adds a reminder whenever a prompt reads like one. Every step below applies the same way to an invoked run: prior art, duplicate check, draft approval, and proposed points. Never skip ahead to a direct `wit_work_item_write` create.

## Step 1: Choose Work Item Type

If `$ARGUMENTS` already names the type unambiguously (`bug`, `user story` / `story`, `feature`, `hot fix` / `hotfix`), use it and skip the question. Name the type in the Step 2 confirmation so the user can correct it. Otherwise, ask the user:

```
What type of work item do you want to create?

  1. Bug          — something deployed is behaving wrong
  2. User Story   — one shippable slice of user-facing behavior
  3. Feature      — a container for several related user stories
  4. Hot Fix      — a production defect that can't wait for the normal queue

Reply with 1, 2, 3, 4, "bug", "user story", "feature", or "hot fix".
```

**Wait for the user's response.** Map the answer to `Bug`, `User Story`, `Feature`, or `Hot Fix`. The Azure DevOps type name is **`Hot Fix`** — two words, that exact casing. (The branch prefix and PR label are `hotfix`, one word — that's a `/implement` concern, not a field value.) If the user types something else, ask again — do not guess.

If the requirements clearly span several independently shippable slices, say so and recommend `Feature` — but the type is still the user's call.

**Bug vs. Hot Fix.** Both describe broken behavior; the difference is urgency, not shape. A Hot Fix ships out-of-band — it targets the production branch directly and skips manual UAT in `/implement`. If the user picks `Hot Fix` for something that reads as a normal-priority defect, say so once and let them decide. If they pick `Bug` for something they describe as production-down, offer `Hot Fix` once and let them decide.

## Step 2: Gather Requirements

Ask the user to describe the requirements:

```
Describe the {feature | bug | user story | hot fix} in your own words. Include:

- What the user is trying to do (or what is broken)
- Why it matters / who is affected
- Any constraints, edge cases, or steps to reproduce (for bugs)
- Links to related work items, PRs, or docs if relevant
- You can also paste image URLs, screenshot links, or attachment URLs —
  they will be preserved in the description

You can paste as much detail as you want — I'll structure it.
```

**Wait for the user's response.** If the response is very short or vague, ask one targeted clarifying question (e.g. "Does this apply to all users or only admins?"). Don't interrogate — one round of clarification is enough.

### Preserve user-supplied images and links

Scan the user's response for:

- Direct image URLs (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`)
- Azure DevOps attachment URLs (e.g. `https://dev.azure.com/.../_apis/wit/attachments/...`) — to look at one before drafting, fetch it with `mcp__azure-devops__wit_work_item_attachment` (the attachment GUID and file name come out of that URL)
- Markdown image syntax (`![alt](url)`)
- Pasted screenshot blob paths or local file paths to images

For each image found, plan to embed it in the final description as an `<img src="{url}">` tag, with the user's surrounding text preserved as context. For non-image links (docs, PRs, related work items), preserve them as `<a href="{url}">{url}</a>` in the relevant section of the draft. Do not strip these — they are often the only ground truth for the requirement.

### Check for prior art (required — do this before drafting)

**Before writing the draft, look for the same process already built somewhere else in the product.** This is not the duplicate check — a duplicate is *the same work already ticketed*. Prior art is *the same process already solved for a different entity, role, or screen*, which the new item should reuse rather than rebuild. The classic shape is "we built X for A; now we want X for B":

> The digital W-9 was built for the **Facility Owner** (AB#3888 → AB#3860), then reused for the **Applicant** (AB#4189) through a shared component set at `Client/src/components/w9/` with a `mode` prop. A later story to give **CDA Trainers** a fillable W-9 (AB#5424) said only "similar process to the facility W-9 process" — naming no work item, no component, no endpoint. That story is a third consumer of an existing wizard whose `W9EntityType` enum already lists `Trainer` on both sides of the stack, but nothing in the item says so, so it reads like a build-from-scratch.

Do all three passes — each finds things the others miss:

1. **The codebase** — search for the noun and the verb in the requirement (`W-9`, `notes`, `export`, `bulk assign`). A `components/` or `shared/` directory, a `mode`/`variant` prop, or an enum listing the new entity alongside existing ones all mean the pattern is already generalized. Say so.
2. **Work items** — `mcp__azure-devops__search_workitem` for the same process against the other entity. Closed items are the useful ones; they name the components and the decisions.
3. **Commits** — `repo_search_commits` for the feature name, to find the PR that landed the original.

Record what you find and carry it into the draft's **Prior Art** section (Step 3). Be specific — work item id, file path, component or endpoint name. "Similar to the facility process" is the failure mode this step exists to prevent; it tells the implementer nothing they can act on.

If you find nothing, say so in one line rather than omitting the section — "no prior art found; this is the first {process} in the product" is itself useful, and it tells the reader the search was actually run.

**Prior art also changes the estimate.** A third consumer of a shared component is a fraction of the first one. Carry the finding into Step 4 and say it in the rationale.

## Step 3: Develop the Plan

Translate the user's free-form requirements into a structured work item draft. The shape depends on the type, but every type serves **two readers**:

- **The PM** reads the **Summary** at the top: plain English, no code.
- **The developer and Claude Code** read everything below it: **technical**, specific, and grounded in the actual codebase. It should be enough to plan and implement the change without rediscovering where it lives.

Neither part substitutes for the other. A plain-English item is unimplementable, and an item that is only technical leaves the PM guessing.

### The Summary — every type, always first

Every work item starts with a **plain-English Summary** written for someone who has never seen the code: a PM, a stakeholder, a support lead. It is the first section of the draft and the first thing on the work item form (Step 8 routes it).

- **2–4 sentences** covering what is changing (or what is broken), who notices, and why it matters. On a Bug or Hot Fix, say what people see go wrong, who is affected, and what "fixed" looks like to them.
- **No technical vocabulary.** That means no code identifiers, file, field, or endpoint names, framework or database names, status codes, or unexplained acronyms. Name things the way a user sees them: the screen, the button, the report, the email. Write "The **Export** button on the Payments page shows an error instead of downloading the file," not "`GET /api/payments/export` returns 500."
- **No code spans.** If a sentence seems to need one, rewrite the sentence. Bold the one key outcome if it helps; the rest is plain prose.
- **Not a copy of the Technical Details.** The Summary is what a PM could repeat in a meeting. The sections below it carry the detail the team needs.

Check it before showing the draft: could a PM understand every word without asking a developer? If not, rewrite it.

### Technical Details — everything below the Summary

The **Technical Details** section replaces a plain-language description. It and the sections after it (acceptance criteria, repro steps, prior art) are written for the developer and for Claude Code running `/implement`. Use the real vocabulary:

- **Ground it in the code.** Start from what Step 2's codebase search found, then read enough of the relevant code to name what changes. Use real file paths, components, classes, services, endpoints and routes, collections or tables, fields, enums, and config keys, all in code spans. Never invent a path or a name. If you couldn't confirm something, mark it **(unverified)**.
- **Say what changes and where, layer by layer.** Cover the UI (screens, components, routes), the API (endpoints, request and response shape, validation), services and business rules, data (new or changed fields, indexes, migrations or backfills), permissions and roles, and integrations or background jobs. Skip a layer the work doesn't touch.
- **Name the rules and constraints.** Include business rules, edge cases, error handling, backward compatibility, and performance or security concerns, plus anything the implementer must not break.
- **It is not the implementation plan.** Name what changes, where, and under which rules. Leave step-by-step code to `/implement`, which plans from this section.
- **No working codebase in the session?** Then say **"Not verified against the code"** at the top of the section and write only what the user told you. Never fill the gap with guessed paths.
- **Sensitive data policy applies.** Never put a PII value or a credential in a work item. Refer to a sensitive field by its purpose ("the tax ID field").

### For a Feature:

```
## Draft: {Prefix} - {proposed title}

**Type:** Feature

### Summary
{2–4 plain-English sentences for a non-technical reader — see "The Summary" above.}

### Technical Details
{The feature-level technical shape. Cover the architecture or approach, the layers and
existing components it touches (real paths), data-model changes, integrations, and the
shared foundation the child stories build on. Note any sequencing constraint: what must
land first sets `Custom.Order` in Step 3F. Leave per-story detail to the stories.}

### Business Value
{Why this is worth building — the problem it removes or the opportunity it opens.}

### Scope
- {each coherent, independently shippable chunk of work — these become the
  child User Stories in Step 3F}
- ...

### Out of Scope
- {anything the user mentioned that shouldn't ride along with this feature}

### Success Criteria
1. {observable, feature-level outcome that proves the capability landed}
2. ...

### Prior Art
- {the same process already built elsewhere — work item id, component/file path,
  endpoint — and what should be reused vs. built new. One line of "none found"
  if the Step 2 search came up empty.}

### Open Questions
- {anything ambiguous that you couldn't infer}
```

A Feature carries **no story points** and **never moves to `Dev Ready`** — sizing and state live on its child stories. Step 4 is skipped for Features.

### For a User Story:

```
## Draft: {Prefix} - {proposed title}

**Type:** User Story

### Summary
{2–4 plain-English sentences for a non-technical reader — see "The Summary" above.}

### Technical Details
{What changes and where, layer by layer: the UI components and routes, API endpoints
(with request/response shape and validation), services and business rules, data fields
and migrations, and permissions. Use real paths and names from the code. Include the
rules, edge cases, and constraints the implementer must respect. This is what
`/implement` plans from, and it never moves to the Task.}

### Acceptance Criteria
1. {Given/When/Then or numbered behavior — must be testable}
2. ...
3. ...

### Out of Scope
- {anything the user mentioned but that shouldn't block this story}

### Prior Art
- {the same process already built elsewhere — work item id, component/file path,
  endpoint — and what should be reused vs. built new. One line of "none found"
  if the Step 2 search came up empty.}

### Open Questions
- {anything ambiguous that you couldn't infer — list as questions, not assumptions}
```

### For a Bug or Hot Fix:

```
## Draft: {Prefix} - {proposed title}

**Type:** {Bug | Hot Fix}
**Priority:** {1 | 2 | 3 | 4}
**Severity:** {1 - Critical | 2 - High | 3 - Medium | 4 - Low}

### Summary
{2–4 plain-English sentences for a non-technical reader — see "The Summary" above.}

### Technical Details
{The failing code path: the screen or component, the endpoint and the request that
fails, and the exact error message, status, log line, or stack trace if known. Name
the likely root cause and where it lives (real file and method), marked
**(suspected)** unless you confirmed it in the code. Include the data condition that
triggers it.}

### Steps to Reproduce
1. ...
2. ...
3. ...

### Expected Behavior
{what should happen}

### Actual Behavior
{what does happen}

### Acceptance Criteria
1. {behavioral check that proves the bug is fixed — must be testable}
2. {regression guard if applicable}

### Environment / Scope
- {where the bug occurs — browser, environment, role, data condition}

### Prior Art
- {the same defect already fixed elsewhere, or the same process working correctly
  for another entity — work item id, component/file path. On a bug this is often
  the fix itself: "the equivalent path for X was fixed in AB#nnnn." One line of
  "none found" if the Step 2 search came up empty.}

### Open Questions
- {anything you couldn't infer}
```

A Hot Fix uses the same draft shape as a Bug. Two differences:

- **Severity and Priority are constrained.** A Hot Fix is by definition urgent — propose Priority `1` (or `2` at the loosest) and Severity `1 - Critical` or `2 - High`. If the requirements don't support that, the item is probably a Bug; say so before drafting.
- **Add a `### Production Impact` section** directly after `### Summary`, naming what is broken right now, which environment, and roughly who is affected. On an out-of-band change, this is the section the reviewer reads right after the Summary. It does not replace the Summary or the Technical Details — the Summary stays plain English for the PM, the Technical Details stay the developer's.

**Inferring Priority and Severity for Bugs and Hot Fixes:**

Propose initial values based on the requirements, then let the user override during approval. Use this rubric:

| Severity | Looks like |
|----------|-----------|
| **1 - Critical** | Production is down, data loss, security breach, or blocking all users |
| **2 - High** | Major feature broken, no workaround, affects many users |
| **3 - Medium** | Feature partially broken, workaround exists, or affects some users |
| **4 - Low** | Cosmetic, minor inconvenience, or affects few users |

| Priority | Looks like |
|----------|-----------|
| **1** | Drop everything — fix immediately |
| **2** | Next sprint at the latest |
| **3** | Normal queue |
| **4** | Nice to have / fix when convenient |

Severity describes user impact; Priority describes scheduling urgency. They are independent — a Sev 2 can be Priority 3 if a workaround exists.

### Investment Category and Impact (every type)

Every User Story, Bug and Hot Fix gets an **Investment Category** (`Custom.InvestmentCategory`) and an **Impact** (`Custom.Impact`). Both are restricted picklists on the `Agile - CSI` process, and Serena's Monthly Executive and Backlog Grooming reports rank work by them. Propose both from the requirements, show them directly under the draft title with a one-line reason, and let the user change either. A Feature gets one pair that every child story inherits — the Feature type itself has neither field, so never write them to the Feature.

| Investment Category | Choose it when |
|---------------------|----------------|
| **Strategic Initiative** | part of a named initiative, launch, or client commitment (e.g. C2Q, the AI Assistant, Rotary) |
| **Quick Win** | small (about 3 points or fewer) with value out of proportion to that |
| **Risk Mitigation** | mainly reduces compliance, security, PII, data-integrity, or payment/financial risk |
| **Maintenance** | anything else that keeps the product working or improves it. The default |

| Impact | Choose it when |
|--------|----------------|
| **Strategic** | advances a company-level goal or a client commitment |
| **Large** | materially changes outcomes for many users or for a client |
| **Medium** | meaningfully improves a recurring workflow |
| **Small** | a minor improvement for a limited audience |
| **Tiny/One-off** | cosmetic, an edge case, or a one-time fix |

Impact is the difference the item makes, not its size. Spell the values exactly as above (`Tiny/One-off` included): Azure DevOps rejects anything else. Serena's Teams wizard chooses from the same tables, so an item reads the same whichever way it was created.

**Only where the process has the fields.** Every project on the `Agile - CSI` process has them (CSI Development, CST Development and the rest). Confirm once per session with `mcp__azure-devops__wit_work_item` (`action: get_type`) for the type being created; if `Custom.InvestmentCategory` and `Custom.Impact` aren't in its `fields`, leave both out of the draft, the confirmation, and the create call — writing a field the process doesn't define fails the create.

### Title Prefix

The title MUST start with one of the product prefixes from the project's CLAUDE.md (e.g. `COM`, `CDA`, `PAY`, `AUD`, `SER`, `PSSF`, `TPS`, `MTG`). If the project CLAUDE.md does not define a prefix table, ask the user which prefix to use before drafting. Format is `PREFIX - Title Here`.

### Step 3F: Decompose the Feature into child stories (Features only)

Directly under the Feature draft, in the same message, present the decomposition as a table — one row per proposed child User Story:

```
### Decomposition Plan — {n} child stories

| # | Order | Proposed title | Summary (one line) | Points | Mockup |
|---|-------|----------------|--------------------|--------|--------|
| 1 |   1   | {Prefix} - …   | …                  |   3    | yes    |
| 2 |   1   | {Prefix} - …   | …                  |   2    | no     |
| 3 |   2   | {Prefix} - …   | …                  |   5    | yes    |

**Sequencing:** Order 1 (#1, #2) ships first and the two are independent.
Order 2 (#3) needs #1's endpoint before it can render.

Total: {sum} points across {n} stories.
```

The Order column comes first on purpose — it matches the wave table `/implement` prints for a Feature (`implement.md`, "Execution Waves (Custom.Order)"), so the two commands produce visually identical artifacts.

**Each child is a full User Story draft.** Start from the Feature's **Scope** bullets — each one is a candidate child; if a bullet is really two stories, split it. Draft every child with the User Story shape above: its own plain-English Summary, Technical Details specific to that story (drawn from the Feature's Technical Details and the code), and testable acceptance criteria. The table's Summary column is a one-line version of that child's plain-English Summary — the same no-code rule applies, and it is the text that opens the child's description.

**Every child carries the same prefix as its parent Feature.** Validate all titles up front: an unprefixed child fails at create time, after the Feature already exists.

**Sizing baseline (state it in the draft, above or below the table):**

```
Story points assume a **senior developer working with Claude** — override any
value you disagree with.
```

> **Assume a senior developer working with Claude is the implementer.** Discount for what Claude removes — boilerplate, test scaffolding, mechanical wiring, codebase search. Do NOT discount for ambiguous AC, product decisions, data migrations, cross-team coordination, or verification needing a running environment.

That is the same baseline `/quote`, `/quote-backlog` and `/plan-backlog` estimate against, so a `/quote` run against a story created here should land on the same number. If the two disagree, one of them is wrong — reconcile it rather than explaining the gap away.

Use the modified Fibonacci scale `1, 2, 3, 5, 8`. **No child story may be larger than 8** — a 13 means the decomposition is wrong and that child must be split again.

**Count limits.** Between 2 and 10 child stories. Fewer than 2 means this should have been a User Story — say so and offer to switch the type instead of creating a one-child Feature. More than 10 means the Feature is too big — do NOT silently truncate; offer to (i) merge the smallest related stories or (ii) split this into two Features.

**Order validation — run it as a check, not a vibe:**

1. Orders are positive integers starting at 1, contiguous, no gaps.
2. For every dependency "story A needs story B", require `order(B) < order(A)`. **Equal orders with a dependency between them is an error**, and so is a dependency pointing at a *higher* order.
3. Every story at order N must be buildable against the merged state of orders 1..N-1 only — that is what "stories sharing an order are mutually independent" means.
4. If a check fails, do not present the plan: bump the dependent story's order, renumber, and re-validate first.
5. Render the result as the plain-language **Sequencing** paragraph shown above.

**Mockups are decided per child, not per Feature.** The Feature itself never gets a mockup. Use the same UI heuristic as Step 5 (a screen, a form, a button, a workflow) to set the Mockup column. Non-UI children are marked `No mockup — non-UI work`.

### Approval

After presenting the draft, ask:

```
Approve this draft? (yes / suggest changes / cancel)
```

**Wait for the user.** If they suggest changes, revise the draft and present it again — repeat until they approve or cancel. Do NOT proceed to story points, mockup, or project selection until approved.

For a **Feature**, that one gate approves the ENTIRE plan — the Feature and every child. Alongside ordinary wording changes, `suggest changes` covers these child-level edits:

- `edit 3: <what to change>` — retitle, re-summarize, re-point, or flip the mockup flag on child 3
- `add: <description>` — append a child, give it an order, and re-validate
- `remove 2` — drop a child; re-check that nothing depended on it and renumber the orders to close any gap
- `reorder 3 -> 1` — move a child between waves and re-run every ordering rule
- `split 4` / `merge 2,3` — the two most common reactions to a decomposition

After ANY of these: re-run the order validation, re-render the whole table, and re-ask the gate. Never accept approval of part of the plan.

## Step 4: Propose Story Points

**Skip this step entirely for a Feature.** A Feature's size is the sum of its child stories — the Feature itself gets no `StoryPoints` value and stays in `New`. Its stories were pointed in Step 3F. Go to Step 5.

For a **Bug**, **User Story**, or **Hot Fix**, every work item this command creates gets a story point estimate — proposed automatically, applied only with the user's agreement.

Estimate using the same rubric as `/quote`: the **modified Fibonacci scale** (`1, 2, 3, 5, 8, 13, 21`), calibrated for a **senior developer working with Claude assistance** in a codebase they know. Don't pad for ramp-up, routine architectural decisions, or stack familiarity — only for things a senior cannot shortcut: genuinely novel work, unresolved open questions, cross-team coordination, external dependencies. If the work looks larger than 21 points, recommend splitting the item instead of proposing a number.

Repetition and boilerplate are assisted work — price them near the bottom of the range and size the item by its hardest distinct problem, not by how many files it touches. The full assisted / not-assisted breakdown lives in `/quote` Step 2; that file is the authority if the two ever drift.

Present the estimate:

```
**Proposed estimate:** {n} story points
- {one-line rationale: scope / layers touched / test burden}

Agree? (yes / different number / skip)
```

**Wait for the user.**

- `yes` → the agreed points are set at creation, and the item is moved to **Dev Ready** after creation (Step 8)
- a different number → use the user's number (their call wins); same Dev Ready behavior
- `skip` → create the item without points; it stays in the default `New` state and can be pointed later with `/quote`

Points are never written without the user's explicit agreement.

## Step 5: Offer a Mockup (User Stories and Features — skip for Bugs and Hot Fixes)

If the work item type is **User Story** or **Feature** and the requirements appear to involve UI (a screen, a form, a button, a workflow), ask:

```
Want me to generate an HTML mockup and embed it in the description? (yes / no)
```

If the work item is clearly non-UI (background job, data migration, API-only change), skip this step and note "No mockup — non-UI work."

### If the user says yes:

1. Delegate to the **mockup** agent to generate an HTML mockup based on the draft. Brief the agent with the draft description and acceptance criteria.
2. Save the mockup HTML to a temporary path, then render it to PNG using Playwright (`mcp__playwright__browser_navigate` to the file path, then `mcp__playwright__browser_take_screenshot`).
3. Upload the PNG as a work item attachment via the Azure DevOps API. Capture the returned attachment URL.
4. Append an `<img>` tag to the work item description pointing at the attachment URL, with a caption like `Mockup — generated {date}`.

If any step fails (mockup generation, screenshot, upload), report the failure to the user and ask whether to proceed without the mockup or abort.

### If the user says no:

Continue without a mockup.

## Step 6: Choose the Project

### Detect the default project

Before prompting, attempt to detect the default Azure DevOps project from CLAUDE.md, in this order:

1. **Project CLAUDE.md** — read `<current-repo>/CLAUDE.md`. Look for an explicit `project: <name>` declaration, a "Work items live in **<Project Name>**" sentence, or a `## Pipeline Configuration` table with project references.
2. **Parent CLAUDE.md** — read `<parent-dir>/CLAUDE.md` (e.g. `~/Projects/CLAUDE.md`). Look for the same patterns. The CSI parent CLAUDE.md, for example, declares: "Work items for both **COMPASS** and **CSI Pay** live in the **CSI Development** Azure DevOps project."
3. **Prefix mapping** — if the title prefix chosen in Step 3 is in a known mapping (e.g. `COM`, `CDA`, `PAY`, `MTG` → `CSI Development`), use that.

If a default is found, present it pre-selected:

```
Which Azure DevOps project should this be created in?

  Default: {detected project}   ← press enter to accept

Or specify a different project name.
```

If no default is found, ask without a preselection and offer to list projects via `mcp__azure-devops__core_list_projects`.

**Wait for the user's response.** Validate the project name by calling `mcp__azure-devops__core_list_projects` if the response is ambiguous or doesn't match a known project.

## Step 7: Final Confirmation

Before creating anything in Azure DevOps, present a final summary and ask for one last confirmation:

```
## Ready to Create

**Title:**     {Prefix} - {title}
**Type:**      {Feature | Bug | User Story | Hot Fix}
**Project:**   {project}
**Summary:**   {the plain-English Summary, in full}
{for Bugs and Hot Fixes:}
**Priority:**  {n}
**Severity:**  {n - Label}
{end for Bugs and Hot Fixes}
{for Hot Fixes:}
**Production Impact:** {one line}
{end for Hot Fixes}
{for Features:}
**Child stories:** {n} ({sum} points) — created with the Feature, per the approved Decomposition Plan
{end for Features}
**Investment Category · Impact:** {category} · {impact}{for Features: — on every child story}
**Story Points:** {n (agreed) | skipped | n/a — Features aren't pointed}
**Initial State:** {Dev Ready (pointed) | New (no points) | New (Feature)}
**Mockup:**    {Embedded | Not requested | Skipped (non-UI)}
**Images:**    {count} user-supplied image(s) embedded in description
**Open Questions:** {count}

Create this work item now? (yes / edit / cancel)
```

**Wait for the user.**
- `yes` → proceed to Step 8
- `edit` → ask which field to revise (title, summary, technical details, AC, priority, severity, production impact, investment category, impact, story points, project, mockup), revise it, then re-show this summary
- `cancel` → abort with no work item created and confirm "Cancelled — no work item created."

## Step 8: Render to HTML and Create

### Render Markdown sections to HTML

Azure DevOps description and acceptance criteria fields are HTML — they do not render Markdown. Before submitting, convert the draft sections:

| Markdown                  | HTML                                          |
|---------------------------|-----------------------------------------------|
| `1. item\n2. item`        | `<ol><li>item</li><li>item</li></ol>`         |
| `- item\n- item`          | `<ul><li>item</li><li>item</li></ul>`         |
| `**bold**`                | `<strong>bold</strong>`                       |
| `\n\n` (paragraph break)  | `</p><p>`                                     |
| `\n` (single newline)     | `<br>`                                        |
| `` `code` ``              | `<code>code</code>`                           |
| `### Heading`             | `<h3>Heading</h3>`                            |
| `[text](url)`             | `<a href="url">text</a>`                      |
| `![alt](url)`             | `<img src="url" alt="alt">`                   |

Wrap each top-level section in `<p>...</p>`. Preserve any user-supplied `<img>` tags from Step 2 as-is.

### Emphasis and code spans (required)

A description that is one long paragraph of plain prose is not acceptable — even after Markdown is converted, the rendered output must guide the reader's eye. Before rendering, edit the draft so that:

- **Key terms, values, and outcomes** in each sentence are wrapped in `**bold**` (renders as `<strong>...</strong>`). Bold the noun phrase that carries the claim, not the whole sentence.
- **Code identifiers** — method names, class names, field names, file paths, route paths, JSON keys, env vars, commit hashes, IDs, literal values like `true` / `null` / numeric thresholds — are wrapped in `` `code spans` `` (renders as `<code>...</code>`).
- **Lists** are used instead of comma-separated prose whenever the draft contains 2+ parallel items (steps, files, references, acceptance criteria).
- **Section headings** *inside a field's own content* are kept — they become `<h3>` and structure the rendered output. The draft's **top-level** section headings are different: they are routing labels, not content, and the heading is dropped when its section becomes its own field (see below).

Apply this pass to every section (Technical Details, Production Impact, Acceptance Criteria, Steps to Reproduce, Expected/Actual Behavior, Environment/Scope, Prior Art, Open Questions). Apply it equally to Bugs, Hot Fixes, User Stories, Features, and every child story. **The Summary is the exception:** it gets no code spans and no identifiers (Step 3), only an optional bolded outcome.

### Split the draft into fields — acceptance criteria never go in the description

The Step 3 draft is **one document for the user to read**, not the shape of one field. Before rendering, split it section by section and route each section to its own Azure DevOps field:

**Routing depends on the work item type, and the types do not carry the same fields.** This matters more than it looks: **Azure DevOps accepts a write to a field a type does not have.** The value persists and reads back over the API while no form ever renders it — nothing raises, nothing logs. So a wrong field here is invisible in exactly the way a bug report should never be.

Verify with `mcp__azure-devops__wit_work_item` (`action: get_type`) rather than assuming. In the CSI Development process:

**User Story** — Description and Acceptance Criteria, as you would expect:

| Draft section | Goes to |
|---|---|
| `### Summary` | `System.Description` — the **first** block, under its own `<h3>Summary</h3>` |
| `### Technical Details` | `System.Description`, after the Summary, followed by the mockup `<img>`, user-supplied images, `Out of Scope`, `Prior Art`, and `Open Questions` |
| `### Acceptance Criteria` | `Microsoft.VSTS.Common.AcceptanceCriteria` — **never** also in the description |

**Bug** — its form renders only **Repro Steps** and **System Info**. It has **no Acceptance Criteria field**, and `System.Description` has **no control on the Bug form**, so anything routed there is invisible to a human reader:

| Draft section | Goes to |
|---|---|
| `### Summary`, `### Technical Details`, `### Steps to Reproduce`, `### Expected Behavior`, `### Actual Behavior`, `### Acceptance Criteria`, `### Prior Art`, `### Open Questions` | `Microsoft.VSTS.TCM.ReproSteps` — composed into one document, each under its own `<h3>`, in that order |
| `### Environment / Scope` | `Microsoft.VSTS.TCM.SystemInfo` |
| (the same composed body) | `System.Description` — a labelled **duplicate**, for tools that read it without checking the type. Never unique content. |

Do **not** send `Microsoft.VSTS.Common.AcceptanceCriteria` on a Bug. Still *write* acceptance criteria — they go into the composed body, so the item is still estimable — just not into a field the type does not have.

**Hot Fix** — its form renders **Description** and **Repro Steps**. It has neither an Acceptance Criteria field nor a System Info field:

| Draft section | Goes to |
|---|---|
| `### Summary`, `### Production Impact`, `### Technical Details`, `### Prior Art`, `### Open Questions` | `System.Description`, in that order |
| `### Steps to Reproduce`, `### Expected Behavior`, `### Actual Behavior`, `### Environment / Scope` | `Microsoft.VSTS.TCM.ReproSteps` |

**Feature** — everything renders into `System.Description`, with `### Summary` first (see the Features bullet under *Call the create API*, and Phase 1 below for where the Decomposition block goes).

**The Summary always leads** the field the form displays and keeps its `<h3>Summary</h3>` heading, because it shares that field with other sections. It is never omitted.

**Omit an empty section entirely** — never emit a bare `<h3>` with nothing under it. A heading with no body reads as content that went missing.

**The rendered `System.Description` must not contain an "Acceptance Criteria" heading or its criteria** — not as `<h3>`, not as `<strong>`, not as a bolded line, not "for readability", not "so it reads as a complete document". Azure DevOps renders the AC field as its own section on the work item form, so a copy in the description gives the reader two lists that drift apart while leaving the real field empty. It also breaks estimation: an empty AC field is exactly what `/quote`, `/quote-backlog`, and `/plan-backlog` read to decide an item can't be sized, so criteria in the wrong field make a fully-specified story look unestimable and bounce it back to its creator.

**Drop the section's own heading when it becomes a field.** `Microsoft.VSTS.Common.AcceptanceCriteria` holds the criteria list alone — an `<ol>` or `<ul>`, not `<h3>Acceptance Criteria</h3>` followed by the list. Same for `ReproSteps`. The field label is already on the form.

**On a type that HAS the AC field, always write it explicitly — never leave the placeholder.** Some process templates seed a new item's `Microsoft.VSTS.Common.AcceptanceCriteria` with tip text like `💡 Tip: Add "@serena rewrite" to Description for AI suggestions  Define acceptance criteria: - [ ]  - [ ]  - [ ]`. That is a **placeholder, not content**, and it reads as non-empty to every downstream sweep — an item carrying it looks like it has acceptance criteria when it has none. Writing the field is what clears the placeholder.

This applies to **User Story**. It does **not** apply to Bug or Hot Fix: neither type carries the field, so there is no placeholder to clear and the write would go into a hole. For those two, the criteria live in `ReproSteps` per the routing above — which is also what `/quote` and `/quote-backlog` read to decide a bug is estimable.

### Call the create API

Call `mcp__azure-devops__wit_work_item_write` with `action: "create"`:

- **project**: the chosen project
- **workItemType**: `Feature`, `Bug`, `User Story`, or `Hot Fix` (two words, exact casing)
- **fields**: an **array of `{name, value, format}` objects** — *not* a JSON Patch document. The title is one of them (`System.Title`), not a separate parameter. Every large-text field needs `format: "Html"` or Azure DevOps may interpret it as Markdown. Every `value` is a **string**, so numerics are stringified (`"2"`, `"3"`, `"1"`).

```
mcp__azure-devops__wit_work_item_write
  action:       "create"
  project:      "{project}"
  workItemType: "User Story"
  fields: [
    { name: "System.Title",                             value: "{Prefix} - {title}" },
    { name: "System.Description",                       value: "<h3>Summary</h3><p>…</p><h3>Technical Details</h3>…", format: "Html" },
    { name: "Microsoft.VSTS.Common.AcceptanceCriteria", value: "<ol>…</ol>", format: "Html" }
  ]
```

The example above is a **User Story**. Other types carry different fields, and getting this wrong is invisible: **Azure DevOps accepts a write to a field a work item type does not have.** The value persists and reads back over the API while no form ever renders it — nothing raises, nothing logs. Confirm with `mcp__azure-devops__wit_work_item` (`action: get_type`) rather than assuming.

The fields to set:
  - `System.Title` — the approved title, with its prefix
  - `System.Description` — the rendered HTML: the `<h3>Summary</h3>` block first, then the Technical Details, the embedded mockup `<img>` and any user-supplied images, then the remaining sections per the routing tables above. On a **Bug** this is the labelled duplicate of the composed body, not unique content
  - `Microsoft.VSTS.Common.AcceptanceCriteria` — **User Story only.** The rendered criteria list and **only** the criteria (no `<h3>Acceptance Criteria</h3>` wrapper, and no copy of it in `System.Description`); writing it is what clears the process template's placeholder tip. **Do not send this field on a Bug or a Hot Fix** — neither type has it
  - `Microsoft.VSTS.Scheduling.StoryPoints` — the points agreed in Step 4 (omit entirely if the user skipped, and **always** for a Feature)
  - `Custom.InvestmentCategory` and `Custom.Impact` — the approved values, on a User Story, Bug or Hot Fix. **Never on a Feature**; its pair goes on each child story instead. If a project's process rejects them, retry without them and say so in the confirmation
  - For Features:
    - Render `Summary` first, then `Technical Details`, `Business Value`, `Scope`, `Out of Scope`, `Success Criteria`, and `Prior Art`, into the description. Put `Success Criteria` in `Microsoft.VSTS.Common.AcceptanceCriteria` **only if** the process template exposes that field on Feature — if the create call rejects it, fold the block into the description and retry rather than dropping it.
    - `Microsoft.VSTS.Common.BusinessValue` — only if the user supplied a number. Never invent one.
    - Omit `Microsoft.VSTS.Scheduling.StoryPoints` entirely.
  - For Bugs:
    - `Microsoft.VSTS.TCM.ReproSteps` — the **whole composed body**: summary, technical details, steps, expected behavior, actual behavior, acceptance criteria, prior art and open questions, each under its own `<h3>`. This is the Bug's field of record; its form shows no Description control. The acceptance criteria are folded in here because the Bug type has no Acceptance Criteria field.
    - `Microsoft.VSTS.TCM.SystemInfo` — the `Environment / Scope` section. Omit the field entirely when there is no environment to record, rather than writing an empty value that leaves a blank box on the form.
    - `Microsoft.VSTS.Common.Priority` — the chosen Priority (1–4)
    - `Microsoft.VSTS.Common.Severity` — the chosen Severity (`1 - Critical`, `2 - High`, `3 - Medium`, `4 - Low`)
  - For Hot Fixes:
    - `Microsoft.VSTS.TCM.ReproSteps` — steps, expected behavior, actual behavior and `Environment / Scope` (this type has no System Info field). If the `Hot Fix` type in this process template doesn't expose `ReproSteps`, fold them into `System.Description` rather than dropping them.
    - Render the `Production Impact` section into `System.Description` as an `<h3>` block between the Summary and the Technical Details.
    - No Priority/Severity — a Hot Fix is urgent by definition.

If the `Open Questions` section is non-empty, append it as a clearly-labeled HTML block (`<h3>Open Questions</h3><ul>...</ul>`) **to the field that work item type displays** — the composed `ReproSteps` body on a **Bug**, `System.Description` on a **User Story**, **Hot Fix**, or **Feature**. Putting it in the description of a Bug hides it from every reader.

### Call the create API (Feature — three phases)

A Feature and its children are created in one run, in this order. Nothing is created until the Step 3F plan was approved.

**Phase 1 — the Feature, first.** One `mcp__azure-devops__wit_work_item_write` `action: "create"` with `workItemType: "Feature"` and the `fields[]` shape above. Capture the returned id as `{fid}`.

The Feature's description is assembled in this order: the `<h3>Summary</h3>` block, then `<h3>Technical Details</h3>`, `<h3>Business Value</h3>`, and the other sections from the Features bullet above, then a `<h3>Decomposition</h3>` block, then any open questions. The Decomposition block carries the Step 3F plan **onto the work item** — an HTML `<table>` with one row per child (Order, Story, Points, Depends on, Mockup) followed by the **Sequencing** paragraph rendered as HTML. Without it the ordering rationale exists only in this chat; `/implement` re-derives the waves from `Custom.Order`, but the reviewer reading the Feature in Azure DevOps needs to see *why* the waves are ordered the way they are. (Child AB# ids do not exist yet in Phase 1 — the table names children by title.)

**If Phase 1 fails, stop — create nothing else.** Creating the Feature first is precisely what makes this failure harmless.

**Phase 2 — the children, in ascending execution order.** One `create` per child (`workItemType: "User Story"`), so the AB# sequence matches the wave sequence:

```
mcp__azure-devops__wit_work_item_write
  action:       "create"
  project:      "{project}"
  workItemType: "User Story"
  fields: [
    { name: "System.Title",                             value: "{Prefix} - …" },
    { name: "System.Description",                       value: "<h3>Summary</h3><p>…</p><h3>Technical Details</h3>…", format: "Html" },
    { name: "Microsoft.VSTS.Common.AcceptanceCriteria", value: "<ol>…</ol>", format: "Html" },
    { name: "Microsoft.VSTS.Scheduling.StoryPoints",    value: "3" },
    { name: "Custom.Order",                             value: "1" },
    { name: "Custom.InvestmentCategory",                value: "Strategic Initiative" },
    { name: "Custom.Impact",                            value: "Large" }
  ]
```

Each child is rendered and routed exactly like a standalone User Story: its own `<h3>Summary</h3>` block first, then its Technical Details, then either the mockup `<img>` from Step 5 or the `No mockup — non-UI work` note, with its criteria in `Microsoft.VSTS.Common.AcceptanceCriteria` only.

**`Custom.Order` rejection fallback.** `Custom.Order` comes from an inherited process and may be absent from the User Story form in some projects; `Microsoft.VSTS.Scheduling.StoryPoints` is absent from some templates. If the `create` is rejected because of either, retry that child once *without* both fields, then set them with a follow-up `action: "update"`:

```
mcp__azure-devops__wit_work_item_write
  action:  "update"
  project: "{project}"
  id:      {childId}
  updates: [ { op: "add", path: "/fields/Custom.Order", value: "1" } ]
```

If that also fails, report the child as created *without* an execution order — do not leave it silently unordered. `/implement` treats a child with no `Custom.Order` as a final catch-all wave, so **every** child must end up with a value.

**Phase 3 — link every child to the Feature in ONE call.** `updates` is an array, so this is a single call, not one per child:

```
mcp__azure-devops__wit_work_item_link_write
  action:  "link"
  project: "{project}"
  updates: [
    { id: {fid}, linkToId: {story1Id}, type: "child" },
    { id: {fid}, linkToId: {story2Id}, type: "child" }
  ]
```

`type: "child"` from the Feature is what produces `System.LinkTypes.Hierarchy-Forward` — the link type parameter is a closed enum of friendly names and the literal `System.LinkTypes.Hierarchy-Forward` string is **not** accepted.

**Do NOT use `mcp__azure-devops__wit_work_item_write` `action: "add_child"`.** Its `items[]` accepts only `{title, description, format, areaPath, iterationPath}` — there is no slot for AcceptanceCriteria, StoryPoints, or `Custom.Order`, so children created that way cannot satisfy the field requirements above.

**Partial-failure policy.** Never leave orphans and never roll back — this command has no delete path and must not grow one. If a child create fails mid-run: report which items already exist by AB#, then ask whether to retry the failed child or stop and leave the rest for manual creation. If Phase 3 fails after the children exist, report the ids and the exact link call to retry.

### Move to Dev Ready (pointed items only)

If story points were agreed in Step 4, set `System.State` to `Dev Ready` via `mcp__azure-devops__wit_work_item_write` with `action: "update"` (`id` plus `updates: [ { op: "add", path: "/fields/System.State", value: "Dev Ready" } ]`) **after** the item is created (a separate call — new items start in `New`, and some process templates reject a non-initial state in the create call). If the state transition is rejected, report the error and leave the state as-is — don't silently retry through intermediate states. Items created without points stay in `New`.

The same applies to each child story of a Feature: every child was pointed in Step 3F, so each one gets the same `update` once Phase 3 has linked it.

**Features are never moved.** A Feature stays in `New` and advances only as its child stories are verified and closed — the same rule `/implement` follows.

## Step 9: Confirm

**Read the item back first**, and check the fields that type actually renders — a write to a field the type lacks *succeeds*, so reading back the wrong field proves nothing.

For a **User Story**, fetch `System.Description` and `Microsoft.VSTS.Common.AcceptanceCriteria`:

1. The criteria are in `Microsoft.VSTS.Common.AcceptanceCriteria` — not the placeholder tip, not empty.
2. `System.Description` contains no "Acceptance Criteria" heading and none of the criteria.

For a **Bug**, fetch `Microsoft.VSTS.TCM.ReproSteps` and `Microsoft.VSTS.TCM.SystemInfo`:

1. `ReproSteps` carries every section — summary, technical details, steps, expected, actual, acceptance criteria — each under its own heading.
2. The environment is in `SystemInfo`.
3. No section appears **only** in `System.Description`, which the Bug form does not display.

For a **Hot Fix**, fetch `System.Description` and `Microsoft.VSTS.TCM.ReproSteps`, and confirm the narrative — Summary, then Production Impact, then Technical Details — is in the former and the reproduction detail in the latter.

On **every** type, the displayed field (`System.Description`, or `ReproSteps` on a Bug) opens with the `<h3>Summary</h3>` block, and that block contains no `<code>`. A `Technical Details` block follows it. For a **Feature**, also confirm its description carries the `<h3>Decomposition</h3>` block, and check every child story created in Phase 2 the same way as a User Story, plus its `Custom.Order`.

If a check fails the write didn't take — fix it with `mcp__azure-devops__wit_work_item_write` `action: "update"` before reporting success. Don't report a created item you haven't read back.

After creation, report:

```
Created AB#{id}: {title}
  Project: {project}
  Type: {type}
  Story Points: {n | not set | n/a (Feature)}
  State: {Dev Ready | New}
  URL: {work item URL}
  Mockup attached: {yes / no}
  Acceptance criteria: {n} criteria in the AC field (verified — none in the description)
  Open questions: {count}
{Features only:}
  Child stories: {n created | none — add them later with /plan-backlog}
    AB#{id} (order {n}, {p} pts) — {title}
    ...
{end Features only}

Next steps:
  /explain AB#{id}     — re-read the item in plain language
  /quote AB#{id}       — {re-estimate | set story points (skipped at creation)}
  /implement AB#{id}   — start working on it
```

For a **Feature**, use these next steps instead — `{fid}` is the Feature's id, not a child's:

```
Next steps:
  /explain AB#{fid}     — re-read the feature in plain language
  /plan-backlog         — propose child Tasks for the Dev Ready stories
  /implement AB#{fid}   — implement the child stories in Custom.Order waves
```

`/quote` is not offered for a Feature: its size is the sum of its children, which are already pointed.

Do not assign the work item, set an iteration, or add tags unless the user explicitly asks — those are downstream decisions.

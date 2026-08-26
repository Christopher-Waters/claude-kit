Create a new Azure DevOps work item interactively. Usage: `/create-work-item`

This command walks the user through creating a Feature, Bug, or User Story, develops an acceptance-criteria-ready plan, optionally embeds a UI mockup in the description, and creates the item in the chosen Azure DevOps project. For a Feature it can also draft and create the child User Stories that make the Feature implementable.

Treat `$ARGUMENTS` as an optional rough description that the user may have typed inline (e.g. `/create-work-item users should be able to export payments`). If provided, skip the initial "describe your requirements" prompt in Step 2 and use it as the starting requirements text — but still confirm with the user before proceeding.

## Step 1: Choose Work Item Type

Ask the user:

```
What type of work item do you want to create?

  1. Bug          — something deployed is behaving wrong
  2. User Story   — one shippable slice of user-facing behavior
  3. Feature      — a container for several related user stories

Reply with 1, 2, 3, "bug", "user story", or "feature".
```

**Wait for the user's response.** Map the answer to `Bug`, `User Story`, or `Feature`. If the user types something else, ask again — do not guess.

If the requirements clearly span several independently shippable slices, say so and recommend `Feature` — but the type is still the user's call.

## Step 2: Gather Requirements

Ask the user to describe the requirements:

```
Describe the {feature | bug | user story} in your own words. Include:

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
- Azure DevOps attachment URLs (e.g. `https://dev.azure.com/.../_apis/wit/attachments/...`)
- Markdown image syntax (`![alt](url)`)
- Pasted screenshot blob paths or local file paths to images

For each image found, plan to embed it in the final description as an `<img src="{url}">` tag, with the user's surrounding text preserved as context. For non-image links (docs, PRs, related work items), preserve them as `<a href="{url}">{url}</a>` in the relevant section of the draft. Do not strip these — they are often the only ground truth for the requirement.

## Step 3: Develop the Plan

Translate the user's free-form requirements into a structured work item draft. The shape depends on the type:

### For a Feature:

```
## Draft: {Prefix} - {proposed title}

**Type:** Feature

### Description
{2–4 sentences describing the capability being delivered and who it serves.
A Feature is a container — describe the outcome, not the implementation.}

### Business Value
{Why this is worth building — the problem it removes or the opportunity it opens.}

### Scope
- {each coherent, independently shippable chunk of work — these become the
  child User Stories in Step 9}
- ...

### Out of Scope
- {anything the user mentioned that shouldn't ride along with this feature}

### Success Criteria
1. {observable, feature-level outcome that proves the capability landed}
2. ...

### Open Questions
- {anything ambiguous that you couldn't infer}
```

A Feature carries **no story points** and **never moves to `Dev Ready`** — sizing and state live on its child stories. Step 4 is skipped for Features.

### For a User Story:

```
## Draft: {Prefix} - {proposed title}

**Type:** User Story

### Description
{2–4 sentences in plain language. Explain the user-facing behavior and the
business or user value. Avoid implementation detail — that lives in tasks.}

### Acceptance Criteria
1. {Given/When/Then or numbered behavior — must be testable}
2. ...
3. ...

### Out of Scope
- {anything the user mentioned but that shouldn't block this story}

### Open Questions
- {anything ambiguous that you couldn't infer — list as questions, not assumptions}
```

### For a Bug:

```
## Draft: {Prefix} - {proposed title}

**Type:** Bug
**Priority:** {1 | 2 | 3 | 4}
**Severity:** {1 - Critical | 2 - High | 3 - Medium | 4 - Low}

### Description
{1–2 sentences describing the observed problem in plain language.}

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

### Open Questions
- {anything you couldn't infer}
```

**Inferring Priority and Severity for Bugs:**

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

### Title Prefix

The title MUST start with one of the product prefixes from the project's CLAUDE.md (e.g. `COM`, `CDA`, `PAY`, `AUD`, `SER`, `PSSF`, `TPS`, `MTG`). If the project CLAUDE.md does not define a prefix table, ask the user which prefix to use before drafting. Format is `PREFIX - Title Here`.

### Approval

After presenting the draft, ask:

```
Approve this draft? (yes / suggest changes / cancel)
```

**Wait for the user.** If they suggest changes, revise the draft and present it again — repeat until they approve or cancel. Do NOT proceed to story points, mockup, or project selection until approved.

## Step 4: Propose Story Points

**Skip this step entirely for a Feature.** A Feature's size is the sum of its child stories — the Feature itself gets no `StoryPoints` value and stays in `New`. Its stories are pointed in Step 9. Go to Step 5.

For a **Bug** or **User Story**, every work item this command creates gets a story point estimate — proposed automatically, applied only with the user's agreement.

Estimate using the same rubric as `/quote`: the **modified Fibonacci scale** (`1, 2, 3, 5, 8, 13, 21`), calibrated for a **senior developer working with Claude assistance** in a codebase they know. Don't pad for ramp-up, routine architectural decisions, or stack familiarity — only for things a senior cannot shortcut: genuinely novel work, unresolved open questions, cross-team coordination, external dependencies. If the work looks larger than 21 points, recommend splitting the item instead of proposing a number.

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

## Step 5: Offer a Mockup (User Stories and Features — skip for Bugs)

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
**Type:**      {Feature | Bug | User Story}
**Project:**   {project}
{for Bugs:}
**Priority:**  {n}
**Severity:**  {n - Label}
{end for Bugs}
{for Features:}
**Scope items:** {count} — offered as child stories after creation
{end for Features}
**Story Points:** {n (agreed) | skipped | n/a — Features aren't pointed}
**Initial State:** {Dev Ready (pointed) | New (no points) | New (Feature)}
**Mockup:**    {Embedded | Not requested | Skipped (non-UI)}
**Images:**    {count} user-supplied image(s) embedded in description
**Open Questions:** {count}

Create this work item now? (yes / edit / cancel)
```

**Wait for the user.**
- `yes` → proceed to Step 8
- `edit` → ask which field to revise (title, description, AC, priority, severity, story points, project, mockup), revise it, then re-show this summary
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
- **Section headings** (`### Description`, `### Acceptance Criteria`, etc.) are kept — they become `<h3>` and structure the rendered output.

Apply this pass to every section (Description, Acceptance Criteria, Steps to Reproduce, Expected/Actual Behavior, Environment/Scope, Open Questions). Apply it equally to Bugs and User Stories.

### Call the create API

Call `mcp__azure-devops__wit_create_work_item` with:

- **project**: the chosen project
- **workItemType**: `Feature`, `Bug`, or `User Story`
- **title**: the approved title (with prefix)
- **fields**: a JSON Patch document setting:
  - `System.Description` — the rendered HTML description (with embedded mockup `<img>` and any user-supplied images)
  - `Microsoft.VSTS.Common.AcceptanceCriteria` — the rendered HTML acceptance criteria block
  - `Microsoft.VSTS.Scheduling.StoryPoints` — the points agreed in Step 4 (omit entirely if the user skipped, and **always** for a Feature)
  - For Features:
    - Render `Business Value`, `Scope`, `Out of Scope`, and `Success Criteria` into the description. Put `Success Criteria` in `Microsoft.VSTS.Common.AcceptanceCriteria` **only if** the process template exposes that field on Feature — if the create call rejects it, fold the block into the description and retry rather than dropping it.
    - `Microsoft.VSTS.Common.BusinessValue` — only if the user supplied a number. Never invent one.
    - Omit `Microsoft.VSTS.Scheduling.StoryPoints` entirely.
  - For Bugs:
    - `Microsoft.VSTS.TCM.ReproSteps` — the rendered HTML repro steps (Azure DevOps puts repro steps in this field for the Bug template; if the project uses the Agile template instead, fold repro steps into Description)
    - `Microsoft.VSTS.Common.Priority` — the chosen Priority (1–4)
    - `Microsoft.VSTS.Common.Severity` — the chosen Severity (`1 - Critical`, `2 - High`, `3 - Medium`, `4 - Low`)

If the `Open Questions` section is non-empty, append it to the description as a clearly-labeled HTML block (`<h3>Open Questions</h3><ul>...</ul>`) so the assignee can address it later.

### Move to Dev Ready (pointed items only)

If story points were agreed in Step 4, set `System.State` to `Dev Ready` via `mcp__azure-devops__wit_update_work_item` **after** the item is created (a separate call — new items start in `New`, and some process templates reject a non-initial state in the create call). If the state transition is rejected, report the error and leave the state as-is — don't silently retry through intermediate states. Items created without points stay in `New`.

**Features are never moved.** A Feature stays in `New` and advances only as its child stories are verified and closed — the same rule `/implement` follows.

## Step 9: Offer Child User Stories (Features only)

Skip this step for Bugs and User Stories.

A Feature is a container — `/implement AB#{id}` on a Feature implements its **child User Stories in `Custom.Order` waves**, so a Feature with no children can't be worked. After the Feature is created, ask:

```
Draft child user stories for this feature now? (yes / no — I'll add them later)
```

**Wait for the user.** On `no`, skip to Step 10 and point them at `/plan-backlog` for later.

On `yes`:

1. Turn each bullet from the Feature's **Scope** section into a candidate User Story using the User Story draft shape from Step 3 — plain-language description plus testable acceptance criteria. Keep each one independently shippable; if a bullet is really two stories, split it.
2. Assign each story a **`Custom.Order`** value. Stories that can be built in parallel share the same number; a story that depends on an earlier one gets a higher number. Start at `1` and increment per wave. This field drives the wave ordering in `/implement` — a story with no value lands in a catch-all wave, so set it on every story.
3. Propose story points for each using the Step 4 rubric.
4. Present the whole set for approval at once:

   | # | Order | Proposed Title | Points | Summary |
   |---|-------|----------------|--------|---------|

   ```
   Approve these child stories? (yes / change N / drop N / cancel)
   ```

   **Wait for the user.** Revise and re-present until approved. Do not create anything before approval.
5. On approval, create each story with `mcp__azure-devops__wit_create_work_item` in the same project, setting:
   - `System.Description` and `Microsoft.VSTS.Common.AcceptanceCriteria` — rendered to HTML per the Step 8 rules
   - `Custom.Order` — the wave number
   - `Microsoft.VSTS.Scheduling.StoryPoints` — the agreed points
   - `System.AssignedTo` — copied from the Feature if the Feature has an assignee; otherwise leave unset
6. Link each story to the Feature as a child via `mcp__azure-devops__wit_work_item_link_write` (`System.LinkTypes.Hierarchy-Reverse` from the story to the Feature).
7. Move each pointed story to `Dev Ready` in a follow-up update, per the Step 8 rule. **The Feature's state is never changed.**

If a story fails to create or link, report which ones succeeded and which didn't — don't roll back the Feature.

## Step 10: Confirm

After creation, report:

```
Created AB#{id}: {title}
  Project: {project}
  Type: {type}
  Story Points: {n | not set | n/a (Feature)}
  State: {Dev Ready | New}
  URL: {work item URL}
  Mockup attached: {yes / no}
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

For a **Feature**, use these next steps instead:

```
Next steps:
  /explain AB#{id}     — re-read the feature in plain language
  /plan-backlog        — propose child Tasks for the Dev Ready stories
  /implement AB#{id}   — implement the child stories in Custom.Order waves
```

Do not assign the work item, set an iteration, or add tags unless the user explicitly asks — those are downstream decisions.

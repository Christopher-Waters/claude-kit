Create a new Azure DevOps work item interactively. Usage: `/create-work-item`

This command walks the user through creating a Bug or User Story, develops an acceptance-criteria-ready plan, optionally embeds a UI mockup in the description, and creates the item in the chosen Azure DevOps project.

Treat `$ARGUMENTS` as an optional rough description that the user may have typed inline (e.g. `/create-work-item users should be able to export payments`). If provided, skip the initial "describe your requirements" prompt in Step 2 and use it as the starting requirements text — but still confirm with the user before proceeding.

## Step 1: Choose Work Item Type

Ask the user:

```
What type of work item do you want to create?

  1. Bug
  2. User Story

Reply with 1, 2, "bug", or "user story".
```

**Wait for the user's response.** Map the answer to either `Bug` or `User Story`. If the user types something else, ask again — do not guess.

## Step 2: Gather Requirements

Ask the user to describe the requirements:

```
Describe the {bug | user story} in your own words. Include:

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

The title MUST start with one of the product prefixes from the project's CLAUDE.md (e.g. `COM`, `CDA`, `PAY`, `AUD`, `SER`, `PSSF`, `TPS`). If the project CLAUDE.md does not define a prefix table, ask the user which prefix to use before drafting. Format is `PREFIX - Title Here`.

### Approval

After presenting the draft, ask:

```
Approve this draft? (yes / suggest changes / cancel)
```

**Wait for the user.** If they suggest changes, revise the draft and present it again — repeat until they approve or cancel. Do NOT proceed to mockup or project selection until approved.

## Step 4: Offer a Mockup (User Stories only — skip for Bugs)

If the work item type is **User Story** and the requirements appear to involve UI (a screen, a form, a button, a workflow), ask:

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

## Step 5: Choose the Project

### Detect the default project

Before prompting, attempt to detect the default Azure DevOps project from CLAUDE.md, in this order:

1. **Project CLAUDE.md** — read `<current-repo>/CLAUDE.md`. Look for an explicit `project: <name>` declaration, a "Work items live in **<Project Name>**" sentence, or a `## Pipeline Configuration` table with project references.
2. **Parent CLAUDE.md** — read `<parent-dir>/CLAUDE.md` (e.g. `~/Projects/CLAUDE.md`). Look for the same patterns. The CSI parent CLAUDE.md, for example, declares: "Work items for both **COMPASS** and **CSI Pay** live in the **CSI Development** Azure DevOps project."
3. **Prefix mapping** — if the title prefix chosen in Step 3 is in a known mapping (e.g. `COM`, `CDA`, `PAY` → `CSI Development`), use that.

If a default is found, present it pre-selected:

```
Which Azure DevOps project should this be created in?

  Default: {detected project}   ← press enter to accept

Or specify a different project name.
```

If no default is found, ask without a preselection and offer to list projects via `mcp__azure-devops__core_list_projects`.

**Wait for the user's response.** Validate the project name by calling `mcp__azure-devops__core_list_projects` if the response is ambiguous or doesn't match a known project.

## Step 6: Final Confirmation

Before creating anything in Azure DevOps, present a final summary and ask for one last confirmation:

```
## Ready to Create

**Title:**     {Prefix} - {title}
**Type:**      {Bug | User Story}
**Project:**   {project}
{for Bugs:}
**Priority:**  {n}
**Severity:**  {n - Label}
{end for Bugs}
**Mockup:**    {Embedded | Not requested | Skipped (non-UI)}
**Images:**    {count} user-supplied image(s) embedded in description
**Open Questions:** {count}

Create this work item now? (yes / edit / cancel)
```

**Wait for the user.**
- `yes` → proceed to Step 7
- `edit` → ask which field to revise (title, description, AC, priority, severity, project, mockup), revise it, then re-show this summary
- `cancel` → abort with no work item created and confirm "Cancelled — no work item created."

## Step 7: Render to HTML and Create

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

### Call the create API

Call `mcp__azure-devops__wit_create_work_item` with:

- **project**: the chosen project
- **workItemType**: `Bug` or `User Story`
- **title**: the approved title (with prefix)
- **fields**: a JSON Patch document setting:
  - `System.Description` — the rendered HTML description (with embedded mockup `<img>` and any user-supplied images)
  - `Microsoft.VSTS.Common.AcceptanceCriteria` — the rendered HTML acceptance criteria block
  - For Bugs:
    - `Microsoft.VSTS.TCM.ReproSteps` — the rendered HTML repro steps (Azure DevOps puts repro steps in this field for the Bug template; if the project uses the Agile template instead, fold repro steps into Description)
    - `Microsoft.VSTS.Common.Priority` — the chosen Priority (1–4)
    - `Microsoft.VSTS.Common.Severity` — the chosen Severity (`1 - Critical`, `2 - High`, `3 - Medium`, `4 - Low`)

If the `Open Questions` section is non-empty, append it to the description as a clearly-labeled HTML block (`<h3>Open Questions</h3><ul>...</ul>`) so the assignee can address it later.

## Step 8: Confirm

After creation, report:

```
Created AB#{id}: {title}
  Project: {project}
  Type: {type}
  URL: {work item URL}
  Mockup attached: {yes / no}
  Open questions: {count}

Next steps:
  /explain AB#{id}     — re-read the item in plain language
  /quote AB#{id}       — estimate story points
  /implement AB#{id}   — start working on it
```

Do not assign the work item, set an iteration, or add tags unless the user explicitly asks — those are downstream decisions.

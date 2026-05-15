Fetch a work item and estimate the effort in story points. Usage: `/quote <work-item-id>`

Parse `$ARGUMENTS` to extract the work item ID. Accept formats like `AB#1234`, `#1234`, or just `1234`.

## Step 1: Fetch the Work Item

Read the work item from Azure DevOps using the project from the current repo's CLAUDE.md configuration. Expand with `relations` to include child items and links.

If the work item is not found, report the error and stop.

Capture: title, type, description, acceptance criteria, attached child items, any existing `Story Points` / `Effort` field value, and any tags that hint at scope (e.g. `spike`, `research`, `infra`).

## Step 2: Size the Work

Use the **modified Fibonacci scale** for story points: `1, 2, 3, 5, 8, 13, 21`. Anything that feels larger than 21 should be flagged as "needs to be split" rather than given a number.

Rough sizing rubric (calibrate against what you can see in the repo, not abstract complexity):

| Points | Looks like |
|--------|-----------|
| **1** | Trivial change — copy tweak, single config value, one-line fix. No new tests needed. |
| **2** | Small, well-understood change in one file or one layer. Existing patterns cover it. |
| **3** | Touches a couple of files / one feature slice. Some new tests. No architectural questions. |
| **5** | Crosses layers (e.g. API + UI), or introduces a new component/endpoint following existing patterns. Real test coverage needed. |
| **8** | Multi-area change with meaningful new logic, migrations, or non-trivial edge cases. Some unknowns the implementer will need to resolve. |
| **13** | Large feature, several moving parts, or significant unknowns. Likely benefits from being split. |
| **21** | Very large / high uncertainty. Should almost certainly be split into multiple stories. |

Adjust upward for: unclear acceptance criteria, missing UX, data migrations, cross-team coordination, security/compliance review, or anything tagged `spike`/`research`.

Adjust downward for: pure config changes, mechanical refactors with good test coverage, or work that mirrors an existing implementation.

If the item has child items, size each child as well and present the parent's total as the sum (rounded to the nearest Fibonacci number).

## Step 3: Display the Estimate

Output a compact estimate — not a quote block. Format:

```
**AB#{id}: {title}**
**Estimate:** {points} story points{ — confidence: low/medium/high}

**Reasoning:**
- {bullet on scope / files / layers touched}
- {bullet on unknowns or risk}
- {bullet on test/doc burden}

**Comparable to:** {one-line analogy to a similar past story, or "no obvious comparable in recent work"}
```

If child items were sized, append:

```
**Child breakdown:**
| AB# | Title | Points |
|-----|-------|--------|
| ... | ...   | ...    |
| **Total** |  | **{sum}** |
```

If an existing `Story Points` value is already set on the work item and your estimate differs, call that out explicitly: `**Existing estimate:** {n} (yours differs — {why})`.

If the work looks larger than 21 points, do not assign a number — instead report `**Estimate:** needs to be split` and suggest 2–4 candidate split points based on the acceptance criteria.

## Step 4: Offer to Persist

After displaying the estimate, ask the user: *"Want me to set Story Points = {n} on AB#{id}?"*

Only update the work item if the user explicitly says yes. Do not modify anything otherwise.

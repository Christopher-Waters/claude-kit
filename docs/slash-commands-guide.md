# Slash Commands Guide — Real-World Examples

> This guide walks through every slash command with realistic, step-by-step examples showing exactly what Claude says and what you type back.

---

## /implement — Build a Work Item from Start to Finish

### Example: Implementing a User Story

You have User Story AB#4521: "As an admin, I can export payment history to CSV."

**You type:**
```
/implement AB#4521
```

**Claude responds with a summary:**
```
## AB#4521: Admin Can Export Payment History to CSV

Type: User Story
State: Active
Assigned To: Chris Waters

### Description
Admin users need the ability to export payment history for a selected
organization to a CSV file. The export should include date, amount,
payee name, payment method, and status.

### Acceptance Criteria
1. Export button visible on the Payment History page for admin users only
2. CSV includes columns: Date, Amount, Payee Name, Payment Method, Status
3. Export filters match the current page filters (date range, status)
4. File downloads with name format: PaymentHistory_{OrgName}_{Date}.csv
5. Export handles up to 10,000 records without timeout

Does this look correct? Do you have any additional context or requirements?
```

**You respond:**
```
Looks good. Also make sure the amount column is formatted as currency
with 2 decimal places, and exclude voided payments from the export.
```

**Claude creates the branch** (`story/AB#4521-admin-can-export-payment-history`) and **explores the codebase**, then presents the plan:

```
## Implementation Plan for AB#4521

### Approach
Add a new API endpoint for CSV export and a frontend export button on
the Payment History page. Use the existing PaymentRepository for data
access and add a CsvExportService for file generation.

### Files to Create
- `src/Application/Payments/ExportPaymentHistoryHandler.cs` — CQRS query handler
- `src/Application/Payments/ExportPaymentHistoryQuery.cs` — Query model with filters
- `src/Infrastructure/Services/CsvExportService.cs` — CSV generation using CsvHelper
- `src/client/src/features/payments/components/ExportButton.tsx` — Export button component

### Files to Modify
- `src/API/Controllers/PaymentController.cs` — Add GET /api/payments/export endpoint
- `src/client/src/features/payments/PaymentHistoryPage.tsx` — Add ExportButton to toolbar
- `src/Application/DependencyInjection.cs` — Register CsvExportService

### Agents
- backend: API endpoint, query handler, CSV service
- frontend: Export button component, wire up to page

### Risks / Considerations
- Large exports (10k rows) need streaming response to avoid memory issues
- Amount formatted as currency with 2 decimals per user request
- Voided payments excluded per user request

Approve this plan? (yes / no / suggest changes)
```

**You respond:**
```
yes
```

Claude implements, runs tests/lint/build, then presents the UAT checklist:

```
Automated checks passed and the UAT checklist is ready.

## UAT Checklist
1. [ ] Log in as admin user
2. [ ] Navigate to Payment History page
3. [ ] Verify Export button is visible
4. [ ] Click Export with no filters — verify CSV downloads
5. [ ] Check CSV columns: Date, Amount, Payee Name, Payment Method, Status
6. [ ] Verify amounts show currency format (e.g., $1,234.56)
7. [ ] Verify voided payments are NOT included
8. [ ] Apply date range filter, export again — verify filter applies
9. [ ] Log in as non-admin — verify Export button is NOT visible
10. [ ] Test with large dataset — verify no timeout

Did manual testing pass?
- If YES → reply "testing passed" and I will create the PR
- If NO  → describe what failed
```

**You test and respond:**
```
testing passed
```

Claude creates the PR targeting `develop`, links AB#4521, and updates the work item state.

---

### Example: Implementing a Bug Fix

AB#4589: "Login page shows 500 error when email contains a plus sign."

**You type:**
```
/implement 4589
```

> Note: You can omit the `AB#` prefix.

Claude summarizes, you confirm, Claude plans:

```
## Implementation Plan for AB#4589

### Approach
The email validation regex in LoginValidator rejects '+' characters.
URL encoding issue in the API endpoint also truncates the email at '+'.

### Files to Modify
- `src/Application/Auth/LoginValidator.cs` — Fix email regex to allow '+'
- `src/API/Controllers/AuthController.cs` — URL-decode email parameter
- `tests/Application.Tests/Auth/LoginValidatorTests.cs` — Add test case for plus sign emails

### Agents
- backend: Fix validator regex and URL decoding

Approve this plan? (yes / no / suggest changes)
```

---

### Example: Implementing a Hot Fix

AB#4601: "Production: Payment processing fails for organizations with special characters in name."

You're on the production branch:

```
git checkout main
/implement AB#4601
```

Claude creates `hotfix/AB#4601-payment-processing-fails-for-org`. After implementation and automated checks:

```
Hot Fix ready. All automated checks passed.

Create PR? (yes/no)
```

**You respond:**
```
yes
```

PR is created targeting `main` with a `hotfix` label. No manual UAT required.

---

## /deploy — Quick Commit and Push

### Example: Small fix on a feature branch

```
/deploy "Fix alignment on dashboard header"
```

Claude:
1. Runs `dotnet build` and `npx tsc --noEmit`
2. Shows you the changed files and asks for confirmation
3. Commits with your message
4. Pushes the branch
5. Reports: "Pipeline will trigger on PR merge" (since you're on a feature branch)

### Example: Direct push to develop

You're on `develop` and made a config change:

```
/deploy "Update appsettings for new Redis cache endpoint"
```

Claude commits, pushes, and triggers the Dev CD pipeline. It monitors the build and reports back:

```
Deployed successfully.

Branch: develop
Commit: a1b2c3d - Update appsettings for new Redis cache endpoint
Pipeline: CD - Development (Build #3265) — succeeded
```

---

## /create-release — Group Work Items for Deployment

### Example: Creating a sprint release

You've completed 4 user stories and 2 bug fixes on `develop`. Time to bundle them for staging.

```
/create-release 24
```

**Claude asks:**
```
Which work items should be included in Release #24?

You can provide:
- Specific IDs: AB#4521, AB#4522, AB#4530
- A query: "all Ready for Testing user stories"
- A state filter: "all closed items from Sprint 12"
```

**You respond:**
```
AB#4521, AB#4522, AB#4530, AB#4535, AB#4589, AB#4590
```

**Claude presents:**
```
## Release #24

| ID | Type | Title | State |
|----|------|-------|-------|
| AB#4521 | User Story | Admin can export payment history to CSV | Ready for Testing |
| AB#4522 | User Story | Add bulk payment approval workflow | Ready for Testing |
| AB#4530 | User Story | Dashboard shows monthly payment trends | Ready for Testing |
| AB#4535 | User Story | Email notification on payment failure | Ready for Testing |
| AB#4589 | Bug | Login 500 error with plus sign in email | Ready for Testing |
| AB#4590 | Bug | Pagination resets when changing filters | Ready for Testing |

Create this release with 6 work items? (yes/no)
```

**You respond:**
```
yes
```

**Claude confirms:**
```
Release #24 created with 6 work items.

Work items assigned to Release #24 iteration and tagged with release-24.

To deploy this release to staging:  /deploy-release 24 staging
To deploy this release to production: /deploy-release 24 production
```

---

## /deploy-release — Deploy a Release to an Environment

### Example: Deploying Release #24 to Staging

```
/deploy-release 24 staging
```

**Claude presents the release contents:**
```
## Release #24 — Deploy to staging

| ID | Type | Title | Commits |
|----|------|-------|---------|
| AB#4521 | User Story | Admin can export payment history | 3 commits |
| AB#4522 | User Story | Bulk payment approval workflow | 5 commits |
| AB#4530 | User Story | Dashboard monthly payment trends | 2 commits |
| AB#4535 | User Story | Email notification on payment failure | 2 commits |
| AB#4589 | Bug | Login 500 error with plus sign | 1 commit |
| AB#4590 | Bug | Pagination resets when changing filters | 1 commit |

Deploy Release #24 (6 work items) to staging?

This will:
1. Create a release branch: release/24-to-staging
2. Cherry-pick all commits for the 6 work items
3. Create a PR targeting the staging branch

Proceed? (yes/no)
```

**You respond:**
```
yes
```

**Claude cherry-picks and reports progress:**
```
Cherry-picking commits for Release #24:
[x] AB#4521: Admin can export payment history (3 commits)
[x] AB#4522: Bulk payment approval workflow (5 commits)
[x] AB#4530: Dashboard monthly payment trends (2 commits)
[x] AB#4535: Email notification on payment failure (2 commits)
[x] AB#4589: Login 500 error with plus sign (1 commit)
[x] AB#4590: Pagination resets when changing filters (1 commit)

All commits cherry-picked successfully.
```

**Claude creates the PR:**
```
Release #24 PR created for staging.

PR: https://dev.azure.com/caresolutionsinc/.../_git/.../pullrequest/287
Branch: release/24-to-staging → staging

Work items included:
- AB#4521: Admin can export payment history
- AB#4522: Bulk payment approval workflow
- AB#4530: Dashboard monthly payment trends
- AB#4535: Email notification on payment failure
- AB#4589: Login 500 error with plus sign
- AB#4590: Pagination resets when changing filters

Next steps:
- Review and approve the PR
- Merge triggers the CD pipeline for staging
- Update work item states in Azure DevOps after merge
```

### Example: Deploying the same release to production after staging passes

```
/deploy-release 24 production
```

Same process — cherry-picks from staging to a PR targeting the production branch.

---

## /cherry-pick — Deploy Specific Work Items Without a Release

### Example: Urgent fix needs to go to production but the full release isn't ready

Staging has Release #24 with 6 work items, but only the bug fixes (AB#4589, AB#4590) are urgent and need to go to production now. The user stories need more testing.

```
/cherry-pick AB#4589 AB#4590 production
```

**Claude presents:**
```
## Cherry-Pick to production

| ID | Type | Title | State |
|----|------|-------|-------|
| AB#4589 | Bug | Login 500 error with plus sign in email | Ready for Testing |
| AB#4590 | Bug | Pagination resets when changing filters | Ready for Testing |

Cherry-pick 2 work items to production? (yes/no)
```

**You respond:**
```
yes
```

**Claude creates the PR:**
```
Cherry-pick PR created for production.

PR: https://dev.azure.com/caresolutionsinc/.../_git/.../pullrequest/289
Branch: cherry-pick/2026-03-22-to-production → main

Work items:
- AB#4589: Login 500 error with plus sign in email
- AB#4590: Pagination resets when changing filters

Merge the PR to trigger the CD pipeline for production.
```

### Example: Cherry-picking a single feature to staging for early testing

```
/cherry-pick AB#4521 staging
```

This lets QA start testing the payment export feature on staging while other features are still being developed on `develop`.

---

## /promote — Promote Everything Between Environments

### Example: All staging code is ready for production

Everything on staging has been tested and approved. No need to cherry-pick — promote it all.

```
/promote staging production
```

**Claude shows what will be promoted:**
```
## Promote staging → production

Commits to promote:
| Commit | Message | Work Item |
|--------|---------|-----------|
| a1b2c3d | Add payment export endpoint | AB#4521 |
| d4e5f6a | Add export button component | AB#4521 |
| b7c8d9e | Implement bulk approval workflow | AB#4522 |
| ... | ... | ... |

14 commits will be promoted from staging to production.
Promote? (yes/no)
```

**You respond:**
```
yes
```

Claude creates a PR from `staging` → production branch. Merge triggers the production pipeline.

### Example: Auto-detect the next environment

You're on the `develop` branch and want to promote to staging:

```
/promote
```

Claude auto-detects: "You're on `develop`, the next environment is `staging`." Then shows the same confirmation flow.

---

## /rollback — Revert a Bad Deployment

### Example: A production deploy broke payments

AB#4522 (bulk payment approval) is causing errors in production. You need to revert it immediately.

```
/rollback AB#4522 production
```

**Claude finds the commits and presents:**
```
## Rollback on production

Commits to revert:
| Commit | Message | Work Item |
|--------|---------|-----------|
| b7c8d9e | Implement bulk approval workflow | AB#4522 |
| c9d0e1f | Add approval notification emails | AB#4522 |
| d1e2f3a | Update payment status on approval | AB#4522 |

This will revert 3 commit(s) on production. Proceed? (yes/no)
```

**You respond:**
```
yes
```

Claude reverts, runs pre-flight checks, creates the PR:

```
Rollback PR created for production.

PR: https://dev.azure.com/caresolutionsinc/.../_git/.../pullrequest/291
Branch: revert/2026-03-22-on-production → main

Reverted:
- AB#4522: Bulk payment approval workflow (3 commits)

Merge the PR to trigger the CD pipeline and deploy the rollback.
```

### Example: Revert the last deployment on staging

You don't know which specific work item caused the issue — just roll back whatever was last deployed.

```
/rollback last staging
```

Claude finds the most recent merge commit on `staging`, shows you what it contains, and creates the revert PR after your confirmation.

---

## /review — Code Review a Pull Request

### Example: Reviewing a teammate's PR

```
/review 287
```

**Claude reads the PR and posts:**
```
## Code Review — PR #287: AB#4521 Admin Can Export Payment History

### Summary
Adds CSV export for payment history. 4 new files, 3 modified.

### Findings

**src/Application/Payments/ExportPaymentHistoryHandler.cs**
- Line 42: Query loads all records into memory. For 10k records, use
  IAsyncEnumerable or streaming to avoid OutOfMemoryException.
- Line 67: Amount formatting should use InvariantCulture to prevent
  locale-specific decimal separators in CSV.

**src/API/Controllers/PaymentController.cs**
- Line 128: Missing [Authorize(Roles = "Admin")] on the export endpoint.
  Currently accessible to all authenticated users.

**src/client/src/features/payments/components/ExportButton.tsx**
- Line 15: No loading state — user can click multiple times triggering
  duplicate downloads. Add isLoading state.

### Verdict
3 issues found (1 security, 1 performance, 1 UX).

Approve, Request Changes, or skip the vote?
```

---

## /add-to-release — Add Work Items to an Existing Release

### Example: Forgot a bug fix in Release #24

You already created Release #24 but realized AB#4599 (a bug fix) should be included.

```
/add-to-release 24 AB#4599
```

**Claude shows:**
```
## Release #24 — Adding Work Items

### Currently in Release #24:
| ID | Type | Title | State |
|----|------|-------|-------|
| AB#4521 | User Story | Admin can export payment history | Ready for Testing |
| AB#4522 | User Story | Bulk payment approval workflow | Ready for Testing |
| AB#4530 | User Story | Dashboard monthly payment trends | Ready for Testing |

### Adding:
| ID | Type | Title | State |
|----|------|-------|-------|
| AB#4599 | Bug | Fix export column alignment | Ready for Testing |

Add 1 work item to Release #24? (yes/no)
```

**You respond:**
```
yes
```

**Claude confirms:**
```
1 work item added to Release #24.

Release #24 now contains 4 work items.
```

---

## /status — Check Status of Anything

### Example: Check what's in a release

```
/status release 24
```

```
## Release #24 Status

| ID | Type | Title | State |
|----|------|-------|-------|
| AB#4521 | User Story | Add payment export | Closed |
| AB#4522 | User Story | Bulk approval workflow | Ready for Testing |
| AB#4530 | User Story | Dashboard trends | Ready for Testing |
| AB#4589 | Bug | Login plus sign fix | Closed |

Deployed to:
- Dev: All 4 items
- Staging: All 4 items
- Production: 2 of 4 items
```

### Example: Check pipeline status

```
/status pipeline
```

```
## Recent Pipeline Runs

| Pipeline | Branch | Status | Time |
|----------|--------|--------|------|
| Compass API | main | Succeeded | 2026-03-22 14:26 |
| Compass Client | main | Succeeded | 2026-03-22 14:27 |
| Compass API | develop | Failed | 2026-03-22 10:15 |
```

### Example: Check a work item

```
/status AB#4521
```

Shows the work item details, linked PRs, child tasks, and which environments it's been deployed to.

### Example: Quick overview

```
/status
```

Shows active releases, recent pipeline runs, and open PRs at a glance.

---

## /cleanup-branches — Delete Merged Branches

### Example: Clean up after a sprint

```
/cleanup-branches
```

**Claude finds merged branches:**
```
## Branch Cleanup

### Branches to delete (7):
| Branch | Last Commit | Merged Into |
|--------|-------------|-------------|
| story/AB#4521-admin-export | 2026-03-18 | develop |
| story/AB#4522-bulk-approval | 2026-03-19 | develop |
| bugfix/AB#4589-login-plus-sign | 2026-03-19 | develop |
| release/24-to-staging | 2026-03-21 | staging |
| cherry-pick/2026-03-22-to-production | 2026-03-22 | main |
| T3796 | 2026-03-10 | main |
| U3297 | 2026-03-05 | main |

### Protected (will NOT be deleted):
- main, develop, staging

Delete 7 merged branches? (yes/no)
```

### Example: Preview without deleting

```
/cleanup-branches --dry-run
```

Shows the same list but does not delete anything.

---

## Full Workflow — End to End

Here's a complete real-world scenario tying all commands together:

### Monday: Implement features during the sprint

```
/implement AB#4521    → Export payment history (User Story)
/implement AB#4522    → Bulk payment approval (User Story)
/implement AB#4589    → Fix login plus sign bug (Bug)
```

Each one: summarize → confirm → plan → approve → implement → test → PR → merge to `develop`.

### Wednesday: Review a teammate's PR

```
/review 285           → Review PR for AB#4530 (Dashboard trends)
```

### Thursday: Bundle into a release and deploy to staging

```
/create-release 24    → Group AB#4521, 4522, 4530, 4535, 4589, 4590
/deploy-release 24 staging  → Cherry-pick to staging, create PR
```

Merge the PR. QA tests on staging.

### Friday: QA finds an issue with AB#4522

The bulk approval feature has a bug. Fix it:

```
git checkout develop
/implement AB#4601    → Fix the bulk approval issue
```

After the fix merges to `develop`, cherry-pick it to staging:

```
/cherry-pick AB#4601 staging
```

### Following Monday: Deploy to production

QA approved everything on staging. But AB#4535 (email notifications) needs more work — only deploy the other 5.

```
/cherry-pick AB#4521 AB#4522 AB#4530 AB#4589 AB#4590 production
```

Or create a new release with just those 5:

```
/create-release 25
/deploy-release 25 production
```

### Tuesday: Production issue discovered

AB#4522 is causing intermittent errors in production:

```
/rollback AB#4522 production
```

Revert PR created, merged, production is stable again. Fix the root cause:

```
git checkout develop
/implement AB#4610    → Root cause fix for bulk approval
```

After fix is verified on develop and staging, add it to the release and cherry-pick to production:

```
/add-to-release 25 AB#4610
/cherry-pick AB#4610 production
```

### Wednesday: Check status and clean up

```
/status release 25     → See what's deployed where
/status pipeline       → Check recent build results
/cleanup-branches      → Delete all the merged feature branches from the sprint
```

---

## Quick Reference

| I want to... | Command |
|--------------|---------|
| Build a work item from scratch | `/implement AB#1234` |
| Quick commit and push | `/deploy "message"` |
| Group work items for deployment | `/create-release 24` |
| Add a forgotten item to a release | `/add-to-release 24 AB#4599` |
| Deploy a release to staging | `/deploy-release 24 staging` |
| Deploy a release to production | `/deploy-release 24 production` |
| Send just 2 bug fixes to production | `/cherry-pick AB#1234 AB#1235 production` |
| Promote all staging code to production | `/promote staging production` |
| Revert a bad deploy | `/rollback AB#1234 production` |
| Revert the last deploy | `/rollback last staging` |
| Review a PR | `/review 142` |
| Check what's in a release | `/status release 24` |
| Check pipeline runs | `/status pipeline` |
| Check a work item | `/status AB#4521` |
| See overall project status | `/status` |
| Clean up old branches | `/cleanup-branches` |
| Preview branch cleanup | `/cleanup-branches --dry-run` |

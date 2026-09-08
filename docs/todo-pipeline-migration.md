# Pipeline & Branching Migration TODO

> Created 2026-03-22. Re-baselined 2026-09-06 against the final layout: `main` is the compare branch (never deploys), and each environment has its own lowercase branch — `dev`, `test`, `staging`, `prod` — deployed when a PR merges into it. Items marked done were verified against Azure DevOps on 2026-09-06 (branch lists and pipeline definitions via the MCP server); everything else is unverified and stays open.

---

## Target Layout (every project)

```
feature/AB#…  ──PR──▸  main  ──PR──▸  dev  ──PR──▸  test  ──PR──▸  staging  ──PR──▸  prod
                     (compare)      (Dev)         (Test)         (Staging)        (Production)
```

- [x] `Ready for Staging` and `Staging` states added to User Story, Bug, and Hot Fix in CSI Development (2026-09-06)
- [x] Claude Kit templates updated: slash commands, deployer agent, `CLAUDE-WORKFLOW.md`, `azure-pipelines-template.yml` (2026-09-06)

---

## COMPASS

### Branches
- [x] `main` (compare), `dev`, `test`, `staging`, `prod` all exist
- [ ] Set branch policies: `main` — require PR + build validation + 1 reviewer; `dev`/`test`/`staging` — require PR; `prod` — require PR + approval gate
- [ ] Delete legacy snapshot branches: `currentProd`, `CurrentApiProd`, `CurrentProd12-5`, `Prod-2-9`, `prod-8-21`, `prod-12-19`, `hf/prod-2-17`, `T3856-on-CurrentProd12-5`, `jb-cdaHF-on-Prod-2-9`, `2635_PaymentMethod_And_RegeneratePdf-on-Prod`, `InvoicedDateAndTotalPayeeCount-on-Prod`
- [ ] Delete merged feature branches (`T*`, `U*`, and the ad-hoc named ones) — `/cleanup-branches --dry-run` first

### Pipelines
- [x] `Compass API (YAML)` (ID 32) — exists, last run on `prod` 2026-09-06
- [x] `Compass Client (YAML)` (ID 33) — exists, last run on `prod` 2026-09-06
- [x] Classic `Compass API` (2) and `Compass Client` (3) disabled
- [ ] `CSI.Signal` (19) — still enabled, last run on `main`. Migrate to YAML with `dev`/`test`/`staging`/`prod` triggers, or confirm it's intentionally main-only
- [ ] `PDF Viewer` (24) — still enabled, last run on `main` 2025-07. Same question
- [ ] Delete the disabled classic pipelines once the YAML ones have been stable for a few weeks
- [ ] Disable/delete the classic Release pipeline(s)

### CLAUDE.md
- [ ] Add the Pipeline Configuration table to COMPASS `CLAUDE.md`:
  ```markdown
  ## Pipeline Configuration
  | Branch | Environment | Pipeline(s) |
  |--------|------------|-------------|
  | main | — (compare branch, no deployment) | — |
  | dev | Dev | Compass API (YAML) (32), Compass Client (YAML) (33) |
  | test | Test | Compass API (YAML) (32), Compass Client (YAML) (33) |
  | staging | Staging | Compass API (YAML) (32), Compass Client (YAML) (33) |
  | prod | Production | Compass API (YAML) (32), Compass Client (YAML) (33) |
  ```
  (Add CSI.Signal and PDF Viewer rows once their layout is confirmed.)

---

## CSIPay

### Branches
- [x] Renamed to `main`, `dev`, `test`, `staging`, `prod` — `test` replaced `QA` (commit "Rename pipeline env branches to lowercase; test replaces QA", 2026-09-04)
- [ ] Confirm the old `Dev`, `QA`, `Staging`, `master` branches are deleted (the branch list on 2026-09-06 showed only the five new names — likely done)
- [ ] Set branch policies as for COMPASS
- [ ] Update default/compare branch in repo settings to `main` if not already

### Pipelines
- [x] `CSIPay API` (12) and `CSIPay Client` (13) trigger from the new branches (12 last ran on `dev` 2026-09-04 with the rename commit)
- [ ] Confirm the QA stage is gone from both YAML files and the QA environment resource is removed from Azure DevOps

### CLAUDE.md
- [ ] Add the Pipeline Configuration table to CSIPay `CLAUDE.md`:
  ```markdown
  ## Pipeline Configuration
  | Branch | Environment | Pipeline(s) |
  |--------|------------|-------------|
  | main | — (compare branch, no deployment) | — |
  | dev | Dev | CSIPay API (12), CSIPay Client (13) |
  | test | Test | CSIPay API (12), CSIPay Client (13) |
  | staging | Staging | CSIPay API (12), CSIPay Client (13) |
  | prod | Production | CSIPay API (12), CSIPay Client (13) |
  ```

---

## Glasswing and Monarch (not migrated)

Branches on 2026-09-06: `main`, `develop` only. Pipeline `CD - Development` (28) is disabled; last run on `main` 2026-05-12.

- [ ] Create `dev`, `test`, `staging`, `prod` from `main`
- [ ] Fold `develop` into `main` (or rename `develop` → `dev`) and delete it
- [ ] Add Dev/Test/Staging/Production stages to pipeline 28 (or split per app) with the `dev`/`test`/`staging`/`prod` triggers from `templates/infrastructure/azure-pipelines-template.yml`; re-enable it
- [ ] Determine deployment targets per environment (Azure App Service or IIS)
- [ ] Set branch policies
- [ ] Add the Pipeline Configuration table to Glasswing `CLAUDE.md` (until then, the interim table is `main | — | —` and `develop | Dev | CD - Development (28)`)

---

## All Projects — After Migration

- [ ] Install the latest Claude Kit on each project: `npx @chris1807/claude-kit init --all` (or let the SessionStart auto-update pick it up)
- [ ] Verify `/implement` targets `main` and moves the item to `Code Review`
- [ ] Verify `/deploy` on `main` triggers nothing, and on `dev` triggers the right pipeline
- [ ] Verify `/promote main dev` → `merged` moves items to `Ready for Testing`
- [ ] Test `/create-release` → `/deploy-release N test` → `staging` → `prod` end-to-end on one project, including the gate check and the `merged` state advance
- [ ] Verify `/where` and `/track` treat `main` as "merged, not deployed"

# Pipeline & Branching Migration TODO

> Created 2026-03-22. Track progress by checking items off as they're completed.

---

## COMPASS (Highest Priority)

### Phase 1: Gather Info from Classic Pipelines
- [ ] Open each classic Release pipeline in Azure DevOps portal (Pipelines > Releases)
- [ ] Record for **Compass API**:
  - [ ] IIS website names (Dev, Staging, Production)
  - [ ] IIS app pool names (Dev, Staging, Production)
  - [ ] Physical deploy path on the server
  - [ ] Azure DevOps environment resource names
  - [ ] Deployment group / VM agent names
- [ ] Record for **Compass Client**:
  - [ ] IIS website names (Dev, Staging, Production)
  - [ ] IIS app pool names (Dev, Staging, Production)
  - [ ] Physical deploy path
  - [ ] Environment resource names
- [ ] Record for **CSI.Signal**:
  - [ ] Same as above
- [ ] Record for **PDF Viewer**:
  - [ ] Same as above

### Phase 2: Create YAML Pipelines
- [ ] Copy `templates/infrastructure/azure-pipelines-template.yml` to COMPASS repo
- [ ] Create `azure-pipelines-api.yml` with COMPASS API values (paths: `Api/**`)
- [ ] Create `azure-pipelines-client.yml` with COMPASS Client values (paths: `Client/**`)
- [ ] Create `azure-pipelines-signal.yml` for CSI.Signal
- [ ] Create `azure-pipelines-pdf.yml` for PDF Viewer
- [ ] Push YAML files to COMPASS repo on `main`

### Phase 3: Create Environment Branches
- [ ] Create `develop` branch from `main`
- [ ] Create `staging` branch from `main`
- [ ] Set `develop` as the default branch in Azure DevOps repo settings

### Phase 4: Create New Pipelines in Azure DevOps
- [ ] Create "Compass API" YAML pipeline pointing to `azure-pipelines-api.yml`
- [ ] Create "Compass Client" YAML pipeline pointing to `azure-pipelines-client.yml`
- [ ] Create "CSI.Signal" YAML pipeline pointing to `azure-pipelines-signal.yml`
- [ ] Create "PDF Viewer" YAML pipeline pointing to `azure-pipelines-pdf.yml`
- [ ] Run each pipeline once to verify it works

### Phase 5: Disable Classic Pipelines
- [ ] Disable classic Build pipeline: Compass API (ID 2)
- [ ] Disable classic Build pipeline: Compass Client (ID 3)
- [ ] Disable classic Build pipeline: CSI.Signal (ID 19)
- [ ] Disable classic Build pipeline: PDF Viewer (ID 24)
- [ ] Disable classic Release pipeline(s)
- [ ] Keep disabled for 2 weeks, then delete after new pipelines are proven

### Phase 6: Branch Policies
- [ ] `develop`: Require PR, build validation, at least 1 reviewer
- [ ] `staging`: Require PR, build validation, at least 1 reviewer
- [ ] `main`: Require PR, build validation, at least 1 reviewer, approval gate

### Phase 7: Clean Up
- [ ] Delete old snapshot branches: `currentProd`, `CurrentApiProd`, `Prod-2-9`, `prod-12-19`, `hf/prod-2-17`
- [ ] Delete merged feature branches: `T3796`, `U3297`, etc.

### Phase 8: Add Pipeline Config to CLAUDE.md
- [ ] Add Pipeline Configuration table to COMPASS `CLAUDE.md`:
  ```markdown
  ## Pipeline Configuration
  | Branch | Environment | Pipeline(s) |
  |--------|------------|-------------|
  | develop | Dev | Compass API (ID), Compass Client (ID), CSI.Signal (ID), PDF Viewer (ID) |
  | staging | Staging | Compass API (ID), Compass Client (ID), CSI.Signal (ID), PDF Viewer (ID) |
  | main | Production | Compass API (ID), Compass Client (ID), CSI.Signal (ID), PDF Viewer (ID) |
  ```

---

## Glasswing and Monarch (Medium Priority)

- [ ] Create `staging` branch from `develop`
- [ ] Identify or create a production branch (likely `main`)
- [ ] Add staging and production stages to existing YAML pipeline (ID 28)
  - [ ] Determine staging deployment targets (Azure App Service or IIS)
  - [ ] Determine production deployment targets
  - [ ] Add branch-conditional stages
- [ ] Set branch policies on `staging` and production branch
- [ ] Add Pipeline Configuration table to Glasswing `CLAUDE.md`:
  ```markdown
  ## Pipeline Configuration
  | Branch | Environment | Pipeline(s) |
  |--------|------------|-------------|
  | develop | Dev | CD - Development (28) |
  | staging | Staging | CD - Development (28) |
  | main | Production | CD - Development (28) |
  ```

---

## CSIPay (Low Priority — Do When Convenient)

### Branch Renames (Anytime)
- [ ] Create `develop` branch from `Dev`
- [ ] Create `main` branch from `master`
- [ ] Update `azure-pipelines.yml` triggers: `Dev` → `develop`, `master` → `main`
- [ ] Update `azure-pipelines-client.yml` triggers: same
- [ ] Update stage conditions in both YAML files
- [ ] Update default branch in repo settings to `main`
- [ ] Update branch policies to new names
- [ ] Delete old `Dev` and `master` branches

### Remove QA (~2 months from now)
- [ ] Merge any pending work from `QA` to `Staging`
- [ ] Remove `QA` from triggers in `azure-pipelines.yml`
- [ ] Remove `QA` from triggers in `azure-pipelines-client.yml`
- [ ] Remove QA stage from both YAML files
- [ ] Delete `QA` branch
- [ ] Remove QA environment resource from Azure DevOps

### Add Pipeline Config to CLAUDE.md
- [ ] Add Pipeline Configuration table to CSIPay `CLAUDE.md`:
  ```markdown
  ## Pipeline Configuration
  | Branch | Environment | Pipeline(s) |
  |--------|------------|-------------|
  | Dev | Dev | CSIPay API (12), CSIPay Client (13) |
  | QA | QA | CSIPay API (12), CSIPay Client (13) |
  | Staging | Staging | CSIPay API (12), CSIPay Client (13) |
  | master | Production | CSIPay API (12), CSIPay Client (13) |
  ```

---

## All Projects — After Migration

- [ ] Install latest AI infrastructure on each project: `npx @chris1807/claude-kit init --all`
- [ ] Verify `/implement` creates branches correctly on each project
- [ ] Verify `/deploy` triggers the correct pipeline on each project
- [ ] Verify `/promote` follows the correct environment chain on each project
- [ ] Test `/create-release` and `/deploy-release` end-to-end on one project

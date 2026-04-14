---
name: multicloud-migration-estimator
description: "Use when creating AWS to Azure/GCP migration decision reports from Terraform/OpenTofu IaC, including regional cost (US/EU/AU), effort/risk scoring, and architect recommendations."
---

# Multi-Cloud Migration Estimator Skill

## Purpose
Produce an architect-ready migration decision report that maps AWS services to Azure and GCP, estimates directional costs by region, highlights risks, and recommends a migration path.

## Default Scope
- Search all files under: `input/**`
- Prioritize IaC from: `input/**/src/*.tf`, `input/**/src/tfvar_configs/**/*.tfvars`, `input/**/src/helm/**`
- If `input/` is missing, fallback to `src/**`

## Remote Repository Scope (GitHub MCP)
When the user provides one or more GitHub repository URLs instead of (or in addition to) local files:

1. **Parse repo references** — accept URLs like `https://github.com/{owner}/{repo}` or shorthand `{owner}/{repo}`. Extract owner, repo name, and optional branch/path.
2. **Discover TF files** — for each repo, use the GitHub MCP tool `mcp_github_get_file_contents` to list the repo root and recursively discover `.tf` and `.tfvars` files. Common paths to check:
   - Root directory
   - `src/`, `infra/`, `terraform/`, `infrastructure/`, `iac/`, `deploy/`
   - Any subdirectory structure the user specifies
3. **Fetch file contents** — use `mcp_github_get_file_contents` to read each discovered `.tf` / `.tfvars` / Helm file. Decode Base64-encoded content returned by the API.
4. **Aggregate across repos** — combine all discovered resources into a unified inventory, tagging each resource with its source repo for traceability.
5. **Proceed with standard workflow** — once all remote files are fetched, continue with the normal Workflow steps below (inventory, mapping, costing, risk, recommendation).

### Authentication
- The GitHub MCP server reads the PAT from a `.env` file at the workspace root.
- Users must copy `.env.example` to `.env` and set `GITHUB_PERSONAL_ACCESS_TOKEN` with a token that has `repo` and `read:org` scopes.
- The `.env` file is gitignored and never committed.
- For private repositories, the PAT **must** have `repo` scope. A token with only `public_repo` scope will return 404 errors on private repos.
- If the server fails to start, verify `.env` exists and contains a valid token, then restart the MCP server.

## Required Inputs
- Scope (workspaces/services)
- Planning horizon (months)
- Assumptions:
  - Traffic profile
  - Availability target and DR targets (RTO/RPO)
  - Compliance and residency constraints
  - Performance requirements

If assumptions are incomplete, proceed with explicit "Assumed" labels.

## Workflow
1. **Source discovery** — determine source mode:
   - If the user provides GitHub repo URLs: use `mcp_github_get_file_contents` to list directories and fetch `.tf`, `.tfvars`, and Helm files from each repo. Tag each resource with its source repo (`owner/repo@branch`).
   - If local `input/**` exists: recursively search all files under `input/**`.
   - Fallback: search `src/**`.
   Combine all sources into a unified file set.
2. Discover and inventory AWS resources from the collected IaC files.
3. Group resources by capability:
   - Compute
   - Networking
   - Data
   - Messaging
   - Identity/Security
   - Observability
   - Storage
3. Map each AWS service to Azure and GCP equivalents.
4. Build directional regional cost view for US, EU, and AU.
5. Identify blockers and migration challenges:
   - Feature gaps
   - Data migration complexity
   - IAM/security model changes
   - Network/connectivity changes
   - Operational retraining needs
6. Score effort/risk per capability and produce scenario recommendations.
7. Generate component diagrams for:
   - Current AWS infrastructure (source architecture)
   - Target Azure infrastructure
   - Target GCP infrastructure
   Use Mermaid component/flow diagrams in fenced code blocks so they are renderable in markdown.
   For multiline labels, use `<br/>` instead of `\n` to maximize GitHub Mermaid compatibility.
   Avoid parentheses in `subgraph` titles and critical node labels; use quoted plain text labels such as `subgraph AWS["AWS Account per environment"]`.

## Output Format
Return one markdown report with these sections in order:
1. Executive Summary
2. Source Repository Inventory (when using remote repos — list repos analyzed with branch and file count)
3. Source AWS Footprint
3. Service Mapping Matrix
4. Regional Cost Analysis (Directional)
5. Migration Challenge Register
6. Migration Effort View
7. Decision Scenarios
8. Recommended Plan (30/60/90)
9. Open Questions
10. Component Diagrams
   - AWS Source Component Diagram
   - Azure Target Component Diagram
   - GCP Target Component Diagram

### Report Artifact
- Generate the report content as markdown and save it to the `Reports/` folder.
- Use filename format: `multi-cloud-migration-report-YYYYMMDD-HHMMSS-utc.md`.
- Ensure the saved markdown matches the returned report content.

## Guardrails
- Do not invent discovered resources.
- Mark unknowns as "Not found in IaC".
- Clearly label all pricing as directional estimates.
- Separate one-time migration cost from run-rate cost.
- Include confidence level (High/Medium/Low) for key estimates.

## Writing Style
- Audience: architects and platform leaders.
- Be concise, explicit, and assumption-driven.
- Prefer tables and direct recommendations.

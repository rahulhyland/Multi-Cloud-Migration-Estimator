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
1. Recursively search all files under `input/**`, then discover and inventory AWS resources from IaC.
2. Group resources by capability:
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

## Output Format
Return one markdown report with these sections in order:
1. Executive Summary
2. Source AWS Footprint
3. Service Mapping Matrix
4. Regional Cost Analysis (Directional)
5. Migration Challenge Register
6. Migration Effort View
7. Decision Scenarios
8. Recommended Plan (30/60/90)
9. Open Questions

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

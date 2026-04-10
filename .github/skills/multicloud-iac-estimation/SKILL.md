---
name: multicloud-iac-estimation
description: 'Scan Terraform or OpenTofu infrastructure that defines AWS workloads, classify the source estate, map services to Azure and Google Cloud, and produce a full migration-oriented assessment. Use for AWS IaC review, OpenTofu scans, Terraform analysis, Azure mapping, GCP mapping, and cross-cloud migration planning.'
argument-hint: 'Describe the IaC paths, source cloud assumptions, and whether you need inventory, service mapping, effort estimates, or a full migration report.'
---

# Multi-Cloud IaC Estimation

## What This Skill Produces

This skill turns Terraform or OpenTofu infrastructure into a migration-ready assessment. It is designed for repositories where AWS is the source platform and Azure and Google Cloud Platform are target options.

The skill produces some or all of the following:
- A verified source infrastructure inventory from Terraform or OpenTofu files
- Service mappings from AWS to Azure and GCP
- Assumption-driven migration risks and effort estimates
- Directional cost and operational comparisons
- A concise recommendation for Azure, GCP, or a phased multi-cloud path

Default behavior when the prompt is vague:
- Treat AWS as the source cloud
- Treat Azure and GCP as comparison targets
- Produce a full migration assessment rather than stopping at inventory only

## When To Use

Use this skill when the request includes any of these patterns:
- Scan OpenTofu files that define AWS infrastructure
- Review Terraform or OpenTofu for AWS cloud workloads
- Estimate migration from AWS to Azure or GCP
- Build a cloud service mapping matrix
- Summarize Terraform or OpenTofu infrastructure by capability
- Produce migration blockers, cost drivers, or effort views

Do not use this skill for these cases:
- Greenfield cloud design with no source IaC to inspect
- Runtime debugging of deployed environments
- Contract-grade pricing or procurement quotes

## Supported Domains

### AWS Source Discovery
- Provider blocks, modules, resources, data sources, locals, variables, outputs
- Core AWS services such as compute, networking, storage, databases, messaging, IAM, KMS, observability, DNS, containers, and serverless
- Distinguishing provisioned resources from referenced dependencies

### Terraform And OpenTofu
- `.tf`, `.tfvars`, `.tfvars.json`, and related environment overlays
- Module composition and provider alias usage
- Shared defaults versus environment-specific overrides
- Terraform and OpenTofu syntax treated equivalently unless the repository shows tool-specific behavior

### Azure Target Mapping
- AKS, Container Apps, VM scale sets, Azure Functions
- VNet, Application Gateway, Load Balancer, Front Door, Private Link, DNS
- Azure Storage, Azure Files, Azure NetApp Files, managed databases, Service Bus, Event Grid
- Microsoft Entra ID, workload identity, Key Vault, Monitor, Log Analytics

### GCP Target Mapping
- GKE, Cloud Run, Compute Engine, Cloud Functions
- VPC, Cloud Load Balancing, Cloud Armor, Private Service Connect, Cloud DNS
- Cloud Storage, Filestore, managed databases, Pub/Sub, Eventarc
- IAM, Workload Identity Federation, Secret Manager, Cloud KMS, Cloud Monitoring

## Procedure

### 1. Confirm Scope And Inputs

Start by identifying:
- The IaC root paths to scan
- Whether the repository uses Terraform, OpenTofu, or both
- Whether the goal is inventory only, mapping only, or a full migration assessment
- Whether the user wants workspace-scoped conclusions or a reusable cross-repo summary

If scope is ambiguous, assume:
- Source cloud is AWS
- Target clouds are Azure and GCP
- Pricing is directional
- The expected output is a full migration assessment
- Unknown workload traits must be labeled as assumptions

### 2. Scan The IaC Without Inventing Resources

Read the infrastructure definitions before making claims.

Minimum files to inspect when present:
- Root `.tf` files
- Environment overlays such as `.tfvars` and shared variable sets
- Helm values or Kubernetes manifests referenced by Terraform or OpenTofu
- Supporting input documents that affect migration assumptions

While scanning, separate findings into these buckets:
- Resources created in this repository
- Data sources or external dependencies referenced by this repository
- Inputs that imply capacity, topology, or compliance constraints
- Items not found in IaC

Never upgrade a reference into a discovered resource. If the code only reads an existing VPC, cluster, topic, or secret, report it as a referenced dependency.

### 3. Classify By Capability

Group findings into stable capability buckets:
- Compute
- Networking
- Storage
- Data
- Messaging
- Identity and security
- Observability
- Delivery and platform tooling

For each capability, record:
- AWS services found
- Whether they are provisioned here or only referenced
- Key configuration signals such as region, scaling, encryption, retention, ingress, queue semantics, storage mode, and environment count

### 4. Detect Tooling And Deployment Shape

Decide which IaC interpretation rules matter:
- If the code uses Terraform-style HCL only, treat Terraform and OpenTofu behavior as equivalent unless the repo states otherwise
- If the code uses OpenTofu-specific workflows or lock files, call that out explicitly
- If there are Helm charts or Kubernetes manifests, capture workload topology, scaling hints, and storage patterns
- If variables drive environment fan-out, derive the environment inventory from the actual configs instead of assuming environments

### 5. Map AWS Services To Azure And GCP

For each AWS capability, identify the closest managed target on both clouds.

Use this decision pattern:
1. Prefer managed services that preserve the current operating model
2. If no close match exists, document the redesign explicitly
3. If more than one target service is plausible, choose the primary option and note the alternative briefly
4. Call out where Azure is a closer semantic fit versus where GCP is simpler or cheaper

Examples of common mappings:
- EKS to AKS and GKE
- SQS to Service Bus queues and Pub/Sub subscription-based consumers
- SNS to Service Bus topics and Pub/Sub topics
- KMS to Key Vault Keys and Cloud KMS
- Secrets Manager to Key Vault Secrets and Secret Manager
- ECR to Azure Container Registry and Artifact Registry
- EFS or NFS-style shared storage to Azure Files or Azure NetApp Files and Filestore

### 6. Build Migration Assumptions Explicitly

If the repository does not fully define runtime expectations, add an assumptions block. Include at minimum:
- Traffic profile
- Availability and disaster recovery expectations
- Data residency or compliance constraints
- Performance sensitivity
- Environment isolation expectations

Every assumption must be labeled as assumed, not discovered.

### 7. Estimate Effort, Risk, And Cost Directionally

When asked for estimation, separate:
- Steady-state run cost
- One-time migration cost
- Migration effort by capability
- Migration risk by capability

Use a confidence label for each estimate:
- High when the repository contains concrete sizing and service topology
- Medium when core resources are visible but workload shape is inferred
- Low when major dependencies or traffic data are missing

Keep estimates directional. Do not present them as contractual pricing.

### 8. Produce A Recommendation

End with one of these recommendation types:
- Azure-first
- GCP-first
- Phased multi-cloud

The recommendation must explain why in terms of:
- Service fit
- Migration speed
- Operational risk
- Estimated cost profile

## Decision Points

### Inventory Only vs Full Migration Assessment
- If the user only asks what exists, stop after source inventory and capability grouping
- If the user asks where it should move, add service mappings and migration implications
- If the user asks how much or how hard, include cost, effort, risk, and confidence

### Terraform vs OpenTofu
- If the repository is standard HCL with no OpenTofu-only constructs, do not force a distinction
- If OpenTofu-specific conventions exist, mention compatibility or workflow implications explicitly

### Azure vs GCP Preference
- Favor Azure when the current design depends heavily on Kubernetes, queue semantics close to Service Bus, Microsoft identity alignment, or shared RWX storage
- Favor GCP when compute efficiency, simplified container hosting, or a stronger fit with Pub/Sub style eventing outweighs redesign cost
- Recommend phased multi-cloud only when risk reduction justifies duplicated transition cost

## Quality Checks

Before finishing, verify all of the following:
- Every claimed AWS resource is backed by IaC evidence or labeled as referenced dependency
- Unknowns are marked as assumptions or not found in IaC
- Terraform and OpenTofu terminology matches what the repository actually uses
- Azure and GCP mappings are capability-complete, not cherry-picked
- Costs are separated from effort and labeled as directional
- Confidence levels are present wherever estimates are used
- The final recommendation is justified by the evidence gathered

## Completion Criteria

The skill is complete when the output includes:
- Source infrastructure inventory grouped by capability
- AWS to Azure and GCP mapping coverage for the discovered services
- Explicit assumptions and unknowns
- Migration challenges or blockers
- Directional estimate or recommendation when requested

## Example Prompts

- Scan this OpenTofu repo for AWS infrastructure and summarize it by capability.
- Review these Terraform files and map every AWS service to Azure and GCP equivalents.
- Estimate migration effort from this AWS Terraform stack to AKS and GKE.
- Read the IaC under `src/` and produce a directional Azure vs GCP migration assessment.
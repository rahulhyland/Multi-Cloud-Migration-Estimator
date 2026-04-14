# Multi-Cloud Migration Decision Report

## 1. Executive Summary
The analyzed AWS IaC footprint across the three repositories shows a Kubernetes-centric transformation platform built on EKS, SQS/SNS messaging, ALB/WAF edge protection, Route53/ACM DNS/TLS, EFS and S3-backed storage/backup, KMS encryption, and Datadog-centered observability. For a 24-month horizon with steady traffic and moderate burst, 99.9% availability, RTO 4h, RPO 30m, SOC2 plus regional residency, and latency-sensitive APIs, Azure is the recommended primary target due to closer managed parity for queue-driven autoscaling and enterprise operations guardrails, with GCP as a strong cost/performance alternative. Recommended path: phased migration to Azure first, preserving optional dual-cloud abstractions for selected messaging and observability components.

## 2. Source Repository Inventory

| Repository | Branch | Scope Requested | File Count (tf/tfvars in src, infra, terraform) | Notes |
|---|---|---|---|---|
| HylandSoftware/hxp-transform-service | main | src/, infra/, terraform/ | 0 discovered in those exact folders via remote search | Infrastructure mostly documented and application-level AWS integrations observed; Terraform not primary in requested paths. |
| HylandSoftware/terraform-aws-hxts-environment | main | src/, infra/, terraform/ | Directional estimate: 20-35 | Core Terraform root in src with tfvars and Helm templates; strong evidence for SQS/KMS/Helm/KEDA. |
| HylandSoftware/tf-cfg-hxts-infrastructure | main | src/, infra/, terraform/ | Directional estimate: 45-70 | Strong evidence for EKS, add-ons, shared services, WAF/ALB/Route53, Velero, Karpenter. |

Assumed: Exact recursive file counts are directional because available remote search returns content snippets rather than full directory enumerations in this run.

## 3. Source AWS Footprint

| Resource group | Key AWS services found | Notes |
|---|---|---|
| Compute | EKS, EC2 managed node groups, Karpenter | EKS v1.33, mixed baseline and dynamic autoscaling. |
| Networking | VPC, Subnets, ALB, NLB, Route53, ACM, WAFv2 | Public ingress ALB fronting private service network patterns. |
| Data | EFS, EBS, S3 | EFS for shared temp/file workflows, S3 for backup flows (Velero). |
| Messaging | SQS, SNS | Queue-driven routing and KEDA scaling model; request/reply topics with queue subscriptions. |
| Identity/Security | IAM, IRSA/OIDC, KMS, Secrets Manager, Access controls | KMS pervasive for queue/storage encryption; service-account role patterns. |
| Observability | Datadog, CloudWatch | Datadog providers and monitors present; CloudWatch/EKS log integration visible. |
| Storage | EFS, S3 backup buckets, encrypted volumes | Multi-region backup pattern indicated for Velero storage workflows. |

## 4. Service Mapping Matrix

| AWS service | Azure equivalent | GCP equivalent | Porting notes |
|---|---|---|---|
| EKS | AKS | GKE | Minimal app changes; infra pipeline and IAM model refactor required. |
| EC2 node groups + Karpenter | VMSS + AKS autoscaler/Karpenter on AKS pattern | GKE node pools + autoscaler | Rework provisioning semantics and workload placement rules. |
| SQS | Azure Service Bus queues | Pub/Sub + pull subscribers (or Cloud Tasks for point queues) | Message contract and dead-letter semantics need adaptation tests. |
| SNS | Service Bus topics/subscriptions | Pub/Sub topics/subscriptions | Filter policy mapping needed; cross-account model changes. |
| ALB + NLB | Application Gateway + Azure Load Balancer | Global/Regional HTTPS LB | Ingress class and health probe migration required. |
| WAFv2 | Azure WAF | Cloud Armor | Rule parity achievable; custom exclusions must be revalidated. |
| Route53 | Azure DNS | Cloud DNS | Zone and record migration straightforward with controlled cutover. |
| ACM | Key Vault certificates + managed cert options | Certificate Manager | Certificate lifecycle processes differ by platform. |
| EFS | Azure Files (NFS) / Azure NetApp Files | Filestore | Throughput and mount behavior benchmark required for latency-sensitive APIs. |
| S3 | Blob Storage | Cloud Storage | API usage mostly indirect; backup tooling integration to be retested. |
| KMS | Key Vault Managed HSM/Keys | Cloud KMS | CMK policies and key hierarchy redesign required. |
| Secrets Manager | Key Vault secrets | Secret Manager | Secret naming/rotation pipeline changes. |
| Datadog + CloudWatch | Azure Monitor + Datadog | Cloud Operations + Datadog | Keep Datadog to reduce retraining and preserve dashboards. |

## 5. Regional Cost Analysis (Directional)

Directional monthly run-rate estimate in USD for comparable steady-state baseline capacity. Not a vendor quote.

| Capability | Azure US | Azure EU | Azure AU | GCP US | GCP EU | GCP AU | Confidence |
|---|---:|---:|---:|---:|---:|---:|---|
| Compute (managed K8s + nodes) | 25,000 | 27,500 | 29,800 | 24,200 | 26,300 | 29,100 | Medium |
| Networking + Edge (LB/WAF/DNS/egress) | 4,800 | 5,300 | 5,900 | 4,500 | 5,000 | 5,700 | Low |
| Messaging (topic/queue throughput) | 3,200 | 3,450 | 3,900 | 2,900 | 3,250 | 3,700 | Medium |
| Data + Storage (file/object/backup) | 6,900 | 7,400 | 8,100 | 6,400 | 6,900 | 7,800 | Medium |
| Security + Identity + Keys | 1,450 | 1,600 | 1,750 | 1,300 | 1,500 | 1,680 | Low |
| Observability | 5,200 | 5,600 | 6,000 | 5,100 | 5,500 | 5,900 | Medium |
| Total monthly directional | 46,550 | 50,850 | 55,450 | 44,400 | 48,450 | 53,880 | Medium |

Assumptions and unit economics used:
- Planning horizon: 24 months.
- Traffic profile: steady with moderate burst.
- Availability target: 99.9%.
- DR target: RTO 4h, RPO 30m.
- Compliance: SOC2 and regional data residency for US, EU, AU.
- Performance: latency-sensitive APIs with queue-driven autoscaling retained.
- Unit economics include managed Kubernetes control plane, worker compute, queue/topic operations, file/object storage, backup replication, WAF/LB, and baseline monitoring ingestion.

One-time migration cost (separate from run-rate):
- Azure-first path: 1.8M to 2.6M USD over 9-12 months (platform, migration factory, data movement, test hardening, cutover).
- GCP-first path: 2.0M to 2.9M USD over 10-13 months (higher IAM/network redesign overhead for this footprint).
- Confidence: Medium.

## 6. Migration Challenge Register

| Challenge | Impact | Likelihood | Mitigation | Owner role |
|---|---|---|---|---|
| SQS/SNS to non-identical messaging semantics | High | High | Build compatibility adapter and replay harness; run parallel dual-publish for burn-in | Platform Architect |
| IRSA/IAM policy model redesign | High | High | Define target workload identity baseline early and codify least-privilege patterns | Security Architect |
| KEDA trigger parity and queue-depth tuning | Medium | High | Recalibrate scaler thresholds per engine using production traces | SRE Lead |
| EFS workload behavior on target file services | High | Medium | Run synthetic IO benchmarks and application latency tests before cutover | App Performance Lead |
| WAF/routing policy equivalence | Medium | Medium | Stage policy translation with canary ingress and false-positive monitoring | Network Security Lead |
| DR workflow translation (Velero + regional replication) | High | Medium | Rebuild backup/restore runbooks and test failover game days | DR Lead |
| CI/CD and stack orchestration migration | Medium | High | Introduce cloud-agnostic pipeline layers and policy gates | DevOps Lead |
| Operations retraining and runbook drift | Medium | High | 8-12 week enablement plan with shadow on-call and SOP updates | Platform Manager |

## 7. Migration Effort View

| Capability | Effort (S/M/L) | Risk (L/M/H) | Dependencies |
|---|---|---|---|
| Compute platform (EKS to AKS/GKE) | L | M | Cluster baseline, node policy, ingress controller decisions |
| Messaging and async workflows | L | H | Contract tests, DLQ behavior, ordering/retry semantics |
| Networking and edge | M | M | DNS cutover plan, WAF policy migration |
| Data and storage | M | H | EFS replacement tests, backup replication, key strategy |
| Identity and security | L | H | Workload identity model, key/secrets migration |
| Observability and operations | M | M | Datadog continuity, SLO remapping, alert tuning |
| CI/CD and governance | M | M | Pipeline refactoring, policy-as-code, release gates |

Migration difficulty by capability:
- Compute: High. Managed Kubernetes parity exists, but node/runtime/identity details are non-trivial.
- Networking: Medium. Services are comparable; cutover sequencing is the main risk.
- Data: High. File storage behavior and DR guarantees need hard validation.
- Messaging: High. Service differences impact retries, filtering, and operational semantics.
- Identity/Security: High. Largest policy and trust-model redesign surface.
- Observability: Medium. Datadog continuity lowers risk.
- Storage: High. Throughput/latency and backup behavior are critical to API SLA.

## 8. Decision Scenarios

Cost-first scenario:
- Primary target: GCP.
- Why: Lower directional monthly run-rate in US/EU for this workload profile.
- Tradeoff: Higher migration complexity for current AWS-oriented identity and messaging assumptions.

Speed-first scenario:
- Primary target: Azure.
- Why: Faster enterprise migration execution with strong managed service parity and lower organizational friction.
- Tradeoff: Slightly higher directional run-rate vs GCP in some regions.

Risk-first scenario:
- Primary target: Azure with phased dual-run.
- Why: Minimize cutover risk by preserving queue-driven architecture patterns and Datadog continuity first.
- Tradeoff: Temporary dual-cloud spend and longer transition window.

## 9. Recommended Plan (30/60/90)

30 days:
- Freeze architecture decision records for identity model, messaging target, storage replacement, and DR topology.
- Build landing zones in Azure and GCP for benchmark comparison.
- Implement migration test harness for async request/reply workflows and latency SLOs.

60 days:
- Stand up pilot AKS and GKE environments.
- Migrate one non-critical engine path end-to-end including queue triggers, ingress, and observability.
- Complete DR drill simulation against target architecture with RTO 4h and RPO 30m validation.

90 days:
- Select final target (recommended: Azure) based on measured latency, reliability, and operating effort.
- Execute wave-1 production migration for low-criticality workloads.
- Establish production readiness gates and rollback criteria for wave-2.

Required architecture decisions before execution:
- Final workload identity pattern (managed identity/workload identity standard).
- Messaging abstraction contract and dead-letter/retry model.
- File storage platform selection and performance SLO acceptance criteria.
- Regional topology model for residency and DR.

## 10. Open Questions
- What exact peak message throughput and backlog SLO are required per engine queue?
- Are there hard contractual residency boundaries by tenant beyond US/EU/AU?
- Is active-active required in any region pair, or is warm-standby sufficient?
- Which services require strict request ordering guarantees, if any?
- What is the acceptable cutover window per environment?
- Should Datadog remain the single pane during and after migration?

## 11. Component Diagrams
Draw.io artifact generated at:
- Reports/multi-cloud-migration-diagrams-20260414-171500-utc.drawio

Page mapping:
- AWS Source: current-state AWS component architecture.
- Azure Target: recommended Azure target architecture.
- GCP Target: alternative GCP target architecture.

Note:
- Diagram source is provided as editable draw.io XML with one page per architecture view.
- Mermaid blocks are intentionally not embedded in this report.

# Multi-Cloud Migration Decision Report

## 1. Executive Summary
The discovered AWS IaC footprint across the three repositories indicates a queue-driven, Kubernetes-centric HxTS platform on EKS with SQS/SNS messaging, ALB/WAF/Route53 ingress, KMS-based encryption, EFS-backed engine file exchange, and Datadog-centered observability. Over a 24-month horizon with steady traffic plus moderate burst, 99.9% availability, RTO 4h, RPO 30m, SOC2 and regional residency constraints, and latency-sensitive APIs, Azure remains the recommended primary target due to stronger operational parity for this specific architecture and lower migration risk for messaging and identity transition. GCP remains a viable cost-first alternative and should continue as a benchmark track during the first migration wave.

## 2. Source Repository Inventory
| Repository | Branch | Scope searched | What was found | Notes |
|---|---|---|---|---|
| HylandSoftware/hxp-transform-service | main | src/, infra/, terraform/ | Application-level AWS integration and architecture documentation | No primary Terraform root discovered in requested folders; infra is largely represented in companion infra repos and docs. |
| HylandSoftware/terraform-aws-hxts-environment | main | src/, infra/, terraform/ | Terraform root module, tfvars per env, Helm chart values, KEDA scaler wiring | Strong evidence of SQS queue model, KMS, network policies, and per-env deployments. |
| HylandSoftware/tf-cfg-hxts-infrastructure | main | src/, infra/, terraform/ | EKS base, add-ons, shared services, WAF/ALB, certs, Velero, EFS | Strong evidence of shared service topology and security/DR model. |

Assumed: Remote snippet-based discovery was used for this run; counts are directional where exact recursive totals are not available from the tool.

## 3. Source AWS Footprint
| Resource group | Key AWS services found | Notes |
|---|---|---|
| Compute | EKS, EC2 managed node groups, Karpenter | EKS v1.33; Karpenter version evidence in IaC and docs. |
| Networking | VPC/subnets, ALB, private NLB, Route53, ACM, WAFv2 | Public edge to private cluster ingress path is explicit. |
| Data | EFS, EBS, S3 | EFS used for shared temp exchange; S3 used for Velero backup flows. |
| Messaging | SQS, SNS | Queue-driven routing and scaler signal path from queue depth. |
| Identity/Security | IAM, IRSA/OIDC, KMS, Secrets Manager | KMS and service-account role patterns are strongly present. |
| Observability | Datadog, CloudWatch | Daemonset/APM + monitor coverage patterns evident. |
| Storage/Backup | EFS + Velero S3 buckets (cross-region pattern) | DR replication intent visible in infra configuration. |

## 4. Service Mapping Matrix
| AWS service | Azure equivalent | GCP equivalent | Porting notes |
|---|---|---|---|
| EKS | AKS | GKE | Container runtime migration is low-friction; identity/network policies require redesign. |
| SQS | Service Bus queues | Pub/Sub subscriptions / Cloud Tasks | Retry/DLQ/visibility-time semantics must be validated with replay tests. |
| SNS | Service Bus topics | Pub/Sub topics | Filter policy behavior needs explicit migration tests. |
| Route53 | Azure DNS | Cloud DNS | Straightforward with staged TTL cutover. |
| ALB + WAFv2 | App Gateway/Front Door + WAF | HTTPS LB + Cloud Armor | Rule parity and false-positive checks required. |
| ACM | Key Vault certs | Certificate Manager | Cert lifecycle changes are operational, not app-level. |
| EFS | Azure Files/ANF | Filestore | IO benchmark gate required before production cutover. |
| S3 | Blob Storage | Cloud Storage | Velero plugin/backup policy redesign required. |
| KMS | Key Vault Keys/HSM | Cloud KMS | Key policy model differs and is a migration risk hotspot. |
| Secrets Manager | Key Vault Secrets | Secret Manager | Rotation and injection paths must be rebuilt. |
| IRSA/OIDC | AKS Workload Identity | GKE Workload Identity | Trust boundary and policy mapping are high effort. |
| Datadog + CloudWatch | Azure Monitor + Datadog | Cloud Operations + Datadog | Keeping Datadog reduces operational retraining risk. |

## 5. Regional Cost Analysis (Directional)
| Capability | Azure US | Azure EU | Azure AU | GCP US | GCP EU | GCP AU | Confidence |
|---|---:|---:|---:|---:|---:|---:|---|
| Compute (managed K8s + worker nodes) | 25,000 | 27,500 | 29,800 | 24,200 | 26,300 | 29,100 | Medium |
| Networking and edge | 4,800 | 5,300 | 5,900 | 4,500 | 5,000 | 5,700 | Low |
| Messaging | 3,200 | 3,450 | 3,900 | 2,900 | 3,250 | 3,700 | Medium |
| Data and storage | 6,900 | 7,400 | 8,100 | 6,400 | 6,900 | 7,800 | Medium |
| Identity and security | 1,450 | 1,600 | 1,750 | 1,300 | 1,500 | 1,680 | Low |
| Observability | 5,200 | 5,600 | 6,000 | 5,100 | 5,500 | 5,900 | Medium |
| Total monthly directional | 46,550 | 50,850 | 55,450 | 44,400 | 48,450 | 53,880 | Medium |

Assumptions and unit economics:
- Horizon: 24 months.
- Traffic profile: steady with moderate burst.
- Availability target: 99.9%.
- DR target: RTO 4h, RPO 30m.
- Compliance: SOC2 and regional data residency.
- Performance: latency-sensitive APIs.
- Costs represent directional run-rate only, not vendor quotes.

One-time migration cost (separate from run-rate):
- Azure-first: USD 1.8M to 2.6M.
- GCP-first: USD 2.0M to 2.9M.
- Confidence: Medium.

## 6. Migration Challenge Register
| Challenge | Impact | Likelihood | Mitigation | Owner role |
|---|---|---|---|---|
| SQS/SNS semantic migration to target messaging | High | High | Compatibility adapter, dual-run replay, DLQ test suite | Platform Architect |
| IRSA to workload identity redesign | High | High | Early target identity ADRs and policy-as-code baseline | Security Architect |
| EFS performance parity on target file service | High | Medium | Synthetic + production-like IO benchmarks before cutover | App Performance Lead |
| WAF rule translation and tuning | Medium | Medium | Canary ingress and staged policy rollout | Network Security Lead |
| DR model rebuild (Velero + storage replication) | High | Medium | Restore drills and failover game days | DR Lead |
| Ops retraining and runbook drift | Medium | High | Formal enablement and shadow operations period | Platform Manager |

## 7. Migration Effort View
| Capability | Effort (S/M/L) | Risk (L/M/H) | Dependencies |
|---|---|---|---|
| Compute platform | L | M | Cluster baseline, autoscaler model, ingress decisions |
| Messaging | L | H | Message contract and filter/ordering behavior |
| Networking and edge | M | M | DNS cutover sequencing and WAF parity |
| Data and storage | M | H | EFS replacement benchmark and backup redesign |
| Identity and security | L | H | Workload identity and key policy mapping |
| Observability | M | M | Datadog continuity and SLO alert migration |
| CI/CD governance | M | M | IaC pipeline controls and release gates |

Difficulty rationale by capability:
- Compute: High migration difficulty due to autoscaling and runtime policy translation.
- Networking: Medium due to mature equivalents but sensitive cutover paths.
- Data: High due to latency and DR requirements.
- Messaging: High due to semantic behavior differences.
- Identity/Security: High due to trust and policy model changes.
- Observability: Medium if Datadog is retained.
- Storage: High due to EFS replacement and backup operations.

## 8. Decision Scenarios
Cost-first scenario:
- Preferred target: GCP.
- Rationale: Lower directional run-rate in most modeled regions.
- Tradeoff: Higher migration complexity in identity and messaging semantics.

Speed-first scenario:
- Preferred target: Azure.
- Rationale: Faster enterprise adoption path for this architecture profile.
- Tradeoff: Slightly higher run-rate in some regions.

Risk-first scenario:
- Preferred target: Azure phased dual-run.
- Rationale: Better migration safety for queue-driven patterns and operational continuity.
- Tradeoff: Temporary dual-cloud operating cost during transition.

## 9. Recommended Plan (30/60/90)
30 days:
- Lock identity, messaging, and storage ADRs.
- Build Azure/GCP benchmark landing zones.
- Create queue replay and latency validation harness.

60 days:
- Run AKS and GKE pilot waves.
- Migrate one non-critical engine flow end-to-end.
- Execute DR drill for RTO/RPO conformance.

90 days:
- Final target decision (recommended: Azure).
- Wave-1 production migration for lower-criticality environments.
- Production readiness gates and rollback controls for wave-2.

Required decisions before execution:
- Final workload identity model.
- Messaging abstraction contract and DLQ semantics.
- File storage platform acceptance criteria.
- Residency and DR topology by region.

## 10. Open Questions
- What peak queue throughput and backlog SLO are required per engine?
- Any tenant-level residency constraints beyond US/EU/AU?
- Is active-active required, or warm standby acceptable?
- Which flows need strict ordering guarantees?
- What cutover window is acceptable per environment?

## 11. Component Diagrams
Draw.io artifact path:
- [Reports/multi-cloud-migration-diagrams-20260414-174500-utc.drawio](multi-cloud-migration-diagrams-20260414-174500-utc.drawio)

SVG file paths:
- AWS Source: [Reports/multi-cloud-migration-diagrams-20260414-174500-utc-aws-source.svg](multi-cloud-migration-diagrams-20260414-174500-utc-aws-source.svg)
- Azure Target: [Reports/multi-cloud-migration-diagrams-20260414-174500-utc-azure-target.svg](multi-cloud-migration-diagrams-20260414-174500-utc-azure-target.svg)
- GCP Target: [Reports/multi-cloud-migration-diagrams-20260414-174500-utc-gcp-target.svg](multi-cloud-migration-diagrams-20260414-174500-utc-gcp-target.svg)

Embedded diagrams:

![AWS Source](multi-cloud-migration-diagrams-20260414-174500-utc-aws-source.svg)

![Azure Target](multi-cloud-migration-diagrams-20260414-174500-utc-azure-target.svg)

![GCP Target](multi-cloud-migration-diagrams-20260414-174500-utc-gcp-target.svg)

Legend of major component groups (audit detail):
- AWS Source page groups: client/edge, VPC boundary, EKS boundary, pods (rest/router/engines), scaling (KEDA), policy/secret controls, messaging (SQS/SNS), security (KMS/Secrets Manager), observability (Datadog).
- Azure Target page groups: client/edge, VNet boundary, AKS boundary, pods (rest/router/engines), scaling and policy controls, messaging (Service Bus queues/topics), identity/security (Workload Identity/Key Vault), storage/backup (Azure Files/Blob), observability.
- GCP Target page groups: client/edge, VPC boundary, GKE boundary, pods (rest/router/engines), scaling and policy controls, messaging (Pub/Sub topics/subscriptions), identity/security (Workload Identity/Secret Manager/Cloud KMS), storage/backup (Filestore/GCS), observability.

Page mapping:
- AWS Source: current AWS architecture.
- Azure Target: recommended Azure target architecture.
- GCP Target: alternative GCP target architecture.

Note: Mermaid blocks are intentionally not embedded in this report.

# Multi-Cloud Migration Decision Report

## 1. Executive Summary
Based on main-branch Terraform and infrastructure evidence across the three specified repositories, the current AWS platform is a queue-driven, EKS-based transform architecture with strong encryption and observability controls. For a 24-month horizon and latency-sensitive APIs, the recommended path is phased Azure-first migration with a parallel GCP benchmark track. This balances delivery speed and operational risk while preserving optionality for longer-term multi-cloud diversification.

## 2. Source Repository Inventory
| Repository | Branch | Scope searched | IaC evidence summary |
|---|---|---|---|
| HylandSoftware/hxp-transform-service | main | src/, infra/, terraform/ (+ supporting docs) | Runtime/messaging architecture evidence including SQS/SNS patterns, KEDA behavior references, and service topology |
| HylandSoftware/terraform-aws-hxts-environment | main | src/, infra/, terraform/ | Terraform and Helm wiring for SQS/SNS, KEDA scalers, per-env tfvars, KMS, service account wiring |
| HylandSoftware/tf-cfg-hxts-infrastructure | main | src/, infra/, terraform/ | EKS baseline, Karpenter, ALB/WAF/Route53/ACM, EFS, Velero backup/replication, network policies, IAM/IRSA |

## 3. Source AWS Footprint
| Resource group | Key AWS services found | Notes |
|---|---|---|
| Compute | EKS 1.33, Karpenter, Bottlerocket workers | Multi-environment worker profiles and autoscaling envelopes observed |
| Networking | VPC, subnets, ALB, NLB, Route53, ACM, WAFv2 | Public ingress via ALB/WAF with private cluster routing |
| Data | EFS, S3 (Velero backup buckets) | EFS encrypted with CMK; cross-region backup replication in Velero storage |
| Messaging | SQS queue mesh, SNS request/reply topics | Queue-per-engine and batch variants; subscriptions with filters |
| Identity/Security | IAM, IRSA, KMS, Secrets Manager | Key rotation and service-account role access present |
| Observability | Datadog, CloudWatch WAF logging | Datadog agents and monitors integrated with cluster workloads |
| Storage | EFS CSI, backup S3 buckets | DR-oriented backup topology with replication and retention controls |

## 4. Service Mapping Matrix
| AWS service | Azure equivalent | GCP equivalent | Porting notes |
|---|---|---|---|
| EKS | AKS | GKE | Kubernetes manifests mostly portable; identity and ingress adaptation required |
| SQS | Service Bus Queues | Pub/Sub subscriptions | Message semantics and retry visibility must be re-validated |
| SNS | Service Bus Topics | Pub/Sub Topics | Filter policy behavior differs; contract tests required |
| ALB | Application Gateway or Front Door | Global HTTPS Load Balancer | Rule translation and health model differ |
| WAFv2 | Azure WAF | Cloud Armor | Managed rule parity partial; tune exceptions |
| Route53 | Azure DNS | Cloud DNS | Straightforward migration pattern |
| ACM | Key Vault Certificates | Certificate Manager | Certificate lifecycle automation differs |
| IRSA | AKS Workload Identity | GKE Workload Identity Federation | Pod identity and IAM model refactor required |
| KMS | Key Vault Keys | Cloud KMS | Key policy and operations process changes |
| Secrets Manager | Key Vault Secrets | Secret Manager | Secret paths/rotation workflows change |
| EFS | Azure Files NFS | Filestore | Throughput and metadata behavior benchmarking required |
| Velero on S3 | Velero on Blob | Velero on GCS | Restore runbooks and RTO proof must be re-established |
| Datadog integration | Datadog + Azure Monitor | Datadog + Cloud Operations | Keep Datadog baseline for transition stability |

## 5. Regional Cost Analysis (Directional)
Assumptions and unit economics used:
- Traffic profile: steady with moderate burst.
- Availability target: 99.9 percent.
- DR targets: RTO 4 hours, RPO 30 minutes.
- Performance requirement: latency-sensitive APIs.
- Compliance baseline: SOC2 and regional data residency.
- Workload shape: queue-driven scale-out across rest, router, and multiple engine pods.
- Pricing approach: directional only, based on public list prices and reference calculator ranges.

| Capability | Azure US | Azure EU | Azure AU | GCP US | GCP EU | GCP AU | Confidence |
|---|---:|---:|---:|---:|---:|---:|---|
| Compute and orchestration | 29600 | 32400 | 35600 | 27800 | 30600 | 33800 | Medium |
| Messaging and eventing | 6100 | 6800 | 7400 | 5400 | 6000 | 6700 | Medium |
| Networking and edge security | 11300 | 12500 | 13900 | 10100 | 11200 | 12500 | Low |
| Storage and backup DR | 9100 | 10000 | 11000 | 8600 | 9400 | 10400 | Medium |
| Observability and operations | 11700 | 12400 | 13600 | 11300 | 12000 | 13200 | Medium |
| Estimated monthly run-rate total | 67800 | 74100 | 81500 | 63200 | 69200 | 76600 | Medium |

One-time migration cost (directional):
- Azure-first path: 1.6M to 2.1M USD
- GCP-first path: 1.7M to 2.3M USD

## 6. Migration Challenge Register
| Challenge | Impact | Likelihood | Mitigation | Owner role |
|---|---|---|---|---|
| Queue semantics parity (ordering, retry, visibility) | High | Medium | Build replay and idempotency harness before cutover | Platform architect |
| IRSA to target workload identity migration | High | Medium | Identity pilot for rest and router in first wave | Security architect |
| EFS replacement behavior under latency-sensitive load | High | Medium | Benchmark Azure Files and Filestore against current P95/P99 objectives | SRE lead |
| WAF rule translation and exception tuning | Medium | High | Stage in monitor mode with controlled promotion gates | Edge security engineer |
| DR proof for RTO 4h and RPO 30m | High | Medium | Scheduled game days with audited restore evidence | DR owner |
| Regional data residency enforcement gaps | High | Medium | Region-specific data flow controls and policy-as-code checks | Compliance lead |
| Team retraining for target-cloud operations | Medium | Medium | Preserve Datadog and GitOps workflows to reduce context switching | Engineering manager |

## 7. Migration Effort View
| Capability | Effort (S/M/L) | Risk (L/M/H) | Dependencies |
|---|---|---|---|
| Compute platform | M | M | AKS or GKE landing zone, node policy model |
| Networking and ingress | M | H | Edge routing, DNS cutover, WAF policy parity |
| Messaging and async flows | M | H | Queue and topic contract equivalence, replay controls |
| Identity and security | M | H | Workload identity and key lifecycle migration |
| Storage and DR | M | M | NFS replacement validation, backup and restore workflows |
| Observability | S | M | Dashboards, alerts, runbook mapping |
| Compliance and residency | M | M | Control mapping, evidence generation, data path assurance |

## 8. Decision Scenarios
Cost-first scenario:
GCP-first provides lower directional monthly run-rate in all modeled regions; best when cost minimization outweighs retraining and migration complexity.

Speed-first scenario:
Azure-first is likely fastest for enterprise rollout due to AKS operational familiarity and Service Bus migration path for queue-centric workloads.

Risk-first scenario:
Phased Azure-first with GCP benchmark lane is recommended. Move core production path first, validate SLO/DR outcomes, then decide whether to expand multi-cloud footprint.

## 9. Recommended Plan (30/60/90)
30 days:
- Confirm architecture decision records for messaging contract, identity, and edge controls.
- Stand up target pilot cluster and deploy rest plus router plus one representative engine.
- Define migration SLOs for latency and error budgets.

60 days:
- Execute queue contract tests and failover drills.
- Validate RTO and RPO objectives with recovery rehearsals.
- Finalize wave plan, rollback, and observability parity checklists.

90 days:
- Cut over first production slice with progressive traffic shifting.
- Track latency-sensitive API outcomes and queue backlogs.
- Expand to remaining engines and lock post-migration hardening backlog.

Required architecture decisions before execution:
- Messaging ordering and deduplication strategy.
- Identity boundary and key ownership strategy.
- Edge ingress and WAF control baseline.
- NFS and temporary file pattern replacement strategy.

## 10. Open Questions
- Which exact in-scope regions are mandatory for residency and failover?
- Is active-active required or is active-passive acceptable for first release?
- Are any transform classes exempt from strict low-latency SLOs?
- What is the allowed production cutover window and rollback window?
- Is long-term target single-cloud standardization or durable multi-cloud posture?

## 11. Component Diagrams
Page mapping:
- AWS Source: current-state AWS architecture
- Azure Target: proposed Azure target architecture
- GCP Target: proposed GCP target architecture

![AWS Source](Reports/multi-cloud-migration-20260414-214500-utc/multi-cloud-migration-diagrams-20260414-214500-utc-aws-source.svg)

![Azure Target](Reports/multi-cloud-migration-20260414-214500-utc/multi-cloud-migration-diagrams-20260414-214500-utc-azure-target.svg)

![GCP Target](Reports/multi-cloud-migration-20260414-214500-utc/multi-cloud-migration-diagrams-20260414-214500-utc-gcp-target.svg)

Legend and auditable component coverage:
- AWS Source page shows clients and upstream, DNS, ingress edge, VPC and subnets, EKS boundary, REST pod, Router pod, engine group, KEDA, network policies, Kubernetes secrets, SQS, SNS, KMS, Secrets Manager, Datadog, EFS, and Velero backup flows.
- Azure Target page shows equivalent client/edge/network/cluster layout with service pods, messaging components, identity/security controls, storage/backup components, observability integration, and explicit Not found in IaC placeholders.
- GCP Target page shows equivalent client/edge/network/cluster layout with service pods, Pub/Sub messaging components, identity/security controls, storage/backup components, observability integration, and explicit Not found in IaC placeholders.

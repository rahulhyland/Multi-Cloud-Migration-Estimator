# 1. Executive Summary

This repository describes a multi-environment AWS platform for HxTS centered on EKS, ingress/WAF, SNS/SQS messaging, KMS, EFS, Route53, ACM, Secrets Manager, and Velero backup to S3 with cross-region replication.

Given a 24-month planning horizon and requirements for 99.9% availability, RTO 4h, RPO 30m, SOC2, regional residency, and latency-sensitive APIs, both Azure and GCP are viable. The lowest-risk path is phased platform migration by capability (network edge and observability first, then EKS workloads and messaging, then backup/DR hardening).

Recommended target preference (directional):

- Primary recommendation: GCP-first for lower operational friction on Kubernetes-native patterns and competitive run-rate in this footprint.
- Close alternative: Azure-first if enterprise alignment, identity integration, and commercial commitments outweigh marginal cost differences.

Key estimate summary (directional, all environments, 24 months):

- One-time migration cost: USD 1.8M to 3.2M. Confidence: Medium.
- Run-rate on Azure: roughly 5% to 12% higher than GCP for this specific footprint. Confidence: Low-Medium.
- Highest migration risks: IAM/IRSA redesign, network edge and private connectivity parity, and controlled cutover for SNS/SQS-driven flows.

# 2. Source AWS Footprint

Scope used:

- Terraform root scope: input/**/src/*.tf, all environments.
- Environment evidence from tfvars: dev, staging, prod, prod-eu, sandbox.
- Regions observed in IaC: us-east-1, eu-central-1, eu-west-1 (backup region for EU).

Environment evidence:

- [input/terraform-aws-hxts-environment/src/tfvar_configs/dev.tfvars](input/terraform-aws-hxts-environment/src/tfvar_configs/dev.tfvars)
- [input/terraform-aws-hxts-environment/src/tfvar_configs/staging.tfvars](input/terraform-aws-hxts-environment/src/tfvar_configs/staging.tfvars)
- [input/terraform-aws-hxts-environment/src/tfvar_configs/prod.tfvars](input/terraform-aws-hxts-environment/src/tfvar_configs/prod.tfvars)
- [input/terraform-aws-hxts-environment/src/tfvar_configs/prod-eu.tfvars](input/terraform-aws-hxts-environment/src/tfvar_configs/prod-eu.tfvars)
- [input/terraform-aws-hxts-environment/src/tfvar_configs/sandbox.tfvars](input/terraform-aws-hxts-environment/src/tfvar_configs/sandbox.tfvars)
- [input/tf-cfg-hxts-infrastructure/src/eks/02_eks/tfvar_configs/prod-eu.tfvars](input/tf-cfg-hxts-infrastructure/src/eks/02_eks/tfvar_configs/prod-eu.tfvars)
- [input/tf-cfg-hxts-infrastructure/src/velero_storage/tfvar_configs/prod-eu.tfvars](input/tf-cfg-hxts-infrastructure/src/velero_storage/tfvar_configs/prod-eu.tfvars)

Discovered AWS footprint grouped by capability:

| Capability | AWS services found in IaC | Evidence |
|---|---|---|
| Compute | EKS (module-based), EKS managed add-ons, Helm workloads on EKS, Karpenter | [input/tf-cfg-hxts-infrastructure/src/eks/02_eks/eks.tf](input/tf-cfg-hxts-infrastructure/src/eks/02_eks/eks.tf), [input/tf-cfg-hxts-infrastructure/src/eks/03_eks_addons/eks_managed_addons.tf](input/tf-cfg-hxts-infrastructure/src/eks/03_eks_addons/eks_managed_addons.tf), [input/tf-cfg-hxts-infrastructure/src/eks/02_eks/karpenter.tf](input/tf-cfg-hxts-infrastructure/src/eks/02_eks/karpenter.tf), [input/terraform-aws-hxts-environment/src/hxts.tf](input/terraform-aws-hxts-environment/src/hxts.tf) |
| Networking | ALB/NLB, target groups, security groups, Route53, VPC Endpoint Service, ingress-nginx | [input/tf-cfg-hxts-infrastructure/src/shared_services/alb.tf](input/tf-cfg-hxts-infrastructure/src/shared_services/alb.tf), [input/tf-cfg-hxts-infrastructure/src/eks/03_eks_addons/private_link.tf](input/tf-cfg-hxts-infrastructure/src/eks/03_eks_addons/private_link.tf), [input/tf-cfg-hxts-infrastructure/src/eks/02_eks/ingress.tf](input/tf-cfg-hxts-infrastructure/src/eks/02_eks/ingress.tf) |
| Data | EFS, S3 backup buckets via module, S3 replication | [input/tf-cfg-hxts-infrastructure/src/eks/02_eks/efs.tf](input/tf-cfg-hxts-infrastructure/src/eks/02_eks/efs.tf), [input/tf-cfg-hxts-infrastructure/src/velero_storage/velero_storage.tf](input/tf-cfg-hxts-infrastructure/src/velero_storage/velero_storage.tf) |
| Messaging | SNS topics and policies, SQS queues, SNS subscriptions, SQS policies | [input/tf-cfg-hxts-infrastructure/src/shared_services/transform_communication_topic.tf](input/tf-cfg-hxts-infrastructure/src/shared_services/transform_communication_topic.tf), [input/terraform-aws-hxts-environment/src/transform_communication_queue.tf](input/terraform-aws-hxts-environment/src/transform_communication_queue.tf) |
| Identity/Security | IAM roles/policies/attachments, IRSA roles, KMS CMKs, Secrets Manager, WAF | [input/tf-cfg-hxts-infrastructure/src/eks/03_eks_addons/worker_node_policies.tf](input/tf-cfg-hxts-infrastructure/src/eks/03_eks_addons/worker_node_policies.tf), [input/tf-cfg-hxts-infrastructure/src/shared_services/idp_client.tf](input/tf-cfg-hxts-infrastructure/src/shared_services/idp_client.tf), [input/terraform-aws-hxts-environment/src/kms.tf](input/terraform-aws-hxts-environment/src/kms.tf), [input/tf-cfg-hxts-infrastructure/src/shared_services/waf.tf](input/tf-cfg-hxts-infrastructure/src/shared_services/waf.tf) |
| Observability | CloudWatch log groups, Datadog provider and monitor files, KEDA metrics paths | [input/tf-cfg-hxts-infrastructure/src/shared_services/waf.tf](input/tf-cfg-hxts-infrastructure/src/shared_services/waf.tf), [input/tf-cfg-hxts-infrastructure/src/shared_services/terraform.tf](input/tf-cfg-hxts-infrastructure/src/shared_services/terraform.tf), [input/terraform-aws-hxts-environment/src/provider.tf](input/terraform-aws-hxts-environment/src/provider.tf) |
| Storage | EBS encryption via KMS module, EFS, S3 versioned encrypted buckets with replication | [input/tf-cfg-hxts-infrastructure/src/eks/02_eks/eks.tf](input/tf-cfg-hxts-infrastructure/src/eks/02_eks/eks.tf), [input/tf-cfg-hxts-infrastructure/src/eks/02_eks/efs.tf](input/tf-cfg-hxts-infrastructure/src/eks/02_eks/efs.tf), [input/tf-cfg-hxts-infrastructure/src/velero_storage/velero_storage.tf](input/tf-cfg-hxts-infrastructure/src/velero_storage/velero_storage.tf) |

Not found in IaC:

- Managed relational databases: Not found in IaC.
- Managed cache services: Not found in IaC.
- Direct Kafka/MSK usage: Not found in IaC.

# 3. Service Mapping Matrix

| AWS Service/Pattern | Azure Equivalent | GCP Equivalent | Notes |
|---|---|---|---|
| Amazon EKS | AKS | GKE | Straightforward workload portability if Helm/K8s manifests stay portable. |
| EKS Add-ons and IRSA patterns | AKS Workload Identity + managed add-ons | GKE Workload Identity + add-ons | IAM federation model changes are material. |
| Karpenter | AKS Cluster Autoscaler or Karpenter on AKS where applicable | GKE Node Auto Provisioning / Autopilot | Capacity behavior tuning required for latency-sensitive workloads. |
| ALB + NLB ingress | Application Gateway + Internal Load Balancer | External/Internal HTTP(S) LB + NEG | TLS and path behavior parity needs testing. |
| Route53 | Azure DNS | Cloud DNS | DNS cutover and TTL strategy required. |
| AWS WAF | Azure WAF | Cloud Armor | Rule conversion needed; managed-rule behavior differs. |
| SNS | Service Bus Topics | Pub/Sub Topics | Topic semantics are similar; subscription filters need mapping. |
| SQS | Service Bus Queues | Pub/Sub subscriptions or Cloud Tasks by pattern | Queue ordering/visibility and dead-letter behavior must be mapped carefully. |
| KMS | Key Vault Managed HSM/Keys | Cloud KMS | Key policy and IAM boundary redesign required. |
| Secrets Manager + SSM Parameter Store | Key Vault + App Configuration | Secret Manager + Runtime Config alternatives | Secret path and rotation process migration required. |
| EFS | Azure Files NetApp Files depending throughput | Filestore | Throughput and POSIX semantics validation required. |
| S3 with replication | Blob Storage + object replication | Cloud Storage + bucket replication | Replication SLAs and KMS encryption controls differ. |
| CloudWatch logs | Azure Monitor + Log Analytics | Cloud Logging + Monitoring | Existing Datadog integration can reduce change blast radius. |
| ACM | Key Vault Certificates/App Gateway cert binding | Certificate Manager | Cert issuance/renewal process migration needed. |

# 4. Regional Cost Analysis Directional

Pricing notes:

- Directional estimates only, based on discovered architecture shape, five environments, 24-month horizon, steady traffic with moderate burst, and latency-sensitive APIs.
- Estimates include core platform run-rate only: Kubernetes control/data plane, ingress/LB, messaging, storage, KMS-equivalent, observability baseline, and backup/replication baseline.
- Excludes major app refactor effort and enterprise discount contracts.

Assumed sizing baseline for directional comparison:

- Five environment footprints including prod-eu.
- Per environment: managed Kubernetes cluster with autoscaled worker pools and ingress.
- Messaging: multiple queue/topic pairs and internal processing queues.
- Storage: persistent file storage and object backup replication.

| Region | Azure Estimated Run-rate per month USD | GCP Estimated Run-rate per month USD | Confidence |
|---|---:|---:|---|
| US | 120,000 to 190,000 | 115,000 to 180,000 | Low-Medium |
| EU | 130,000 to 205,000 | 125,000 to 195,000 | Low-Medium |
| AU | 145,000 to 235,000 | 140,000 to 225,000 | Low |

24-month run-rate envelope:

- Azure: USD 2.88M to 5.64M for US baseline equivalent deployment; higher for full EU/AU placement.
- GCP: USD 2.76M to 5.40M for US baseline equivalent deployment; higher for full EU/AU placement.

One-time migration cost estimate:

| Cost Component | Azure USD | GCP USD | Confidence |
|---|---:|---:|---|
| Foundation landing zone, networking, IAM baseline | 280,000 to 520,000 | 260,000 to 500,000 | Medium |
| Kubernetes platform migration and hardening | 520,000 to 900,000 | 480,000 to 860,000 | Medium |
| Messaging and integration migration | 260,000 to 430,000 | 240,000 to 410,000 | Medium |
| Data and backup migration plus DR validation | 220,000 to 420,000 | 220,000 to 420,000 | Medium |
| Observability, security controls, cutover and hypercare | 360,000 to 920,000 | 360,000 to 920,000 | Low-Medium |
| Total one-time | 1,640,000 to 3,190,000 | 1,560,000 to 3,110,000 | Medium |

# 5. Migration Challenge Register

| ID | Challenge | Impact | Likelihood | Risk | Mitigation |
|---|---|---|---|---|---|
| C1 | IRSA to target cloud workload identity migration for many service accounts | High | High | High | Migrate by workload domain, establish identity abstraction layer, run dual-validation in non-prod first. |
| C2 | SNS/SQS semantics to Service Bus or Pub/Sub equivalent | High | Medium | High | Build compatibility matrix for ordering, retry, DLQ, visibility timeout, and filters before cutover. |
| C3 | Ingress and WAF policy parity for latency-sensitive APIs | High | Medium | High | Replay production traffic patterns in pre-prod, tune rule sets and LB timeouts before go-live. |
| C4 | EFS and CSI-dependent workloads portability and performance | Medium | Medium | Medium | Perform file IO benchmark and POSIX behavior tests, adjust storage class and mount options. |
| C5 | Multi-region backup and RPO 30m target validation | High | Medium | High | Validate object replication timing and restore runbooks under load; execute game-days. |
| C6 | Operational retraining across platform and security teams | Medium | High | Medium | Formal enablement program with platform runbooks and SRE shadowing by wave. |
| C7 | Datadog and cloud-native telemetry parity | Medium | Medium | Medium | Keep Datadog as continuity layer while introducing native telemetry incrementally. |
| C8 | Private connectivity and endpoint service behavior differences | Medium | Medium | Medium | Prototype private endpoint flows early and include in Wave 1 foundation testing. |

# 6. Migration Effort View

Effort and risk scoring scale:

- Effort: 1 low to 5 high
- Risk: 1 low to 5 high

| Capability | Effort | Risk | Driver |
|---|---:|---:|---|
| Compute and container platform | 4 | 4 | EKS module-heavy setup, add-ons, Karpenter, and identity coupling. |
| Networking and edge | 4 | 4 | ALB/NLB, WAF, Route53, private endpoint service parity work. |
| Data and storage | 3 | 3 | EFS and S3 replication patterns are portable but require performance and DR validation. |
| Messaging | 4 | 4 | Multiple SNS/SQS queues, filter policies, and consumer scaling coupling. |
| Identity and security | 5 | 5 | Broad IAM role/policy footprint and OIDC-based service account trust model changes. |
| Observability | 3 | 3 | Datadog continuity helps, but alert and metric parity tuning is needed. |
| Operations and governance | 3 | 3 | New cloud operating model and runbook redesign required. |

Overall migration profile:

- Aggregate effort: High.
- Aggregate risk: High without phased rollout; Medium with strict wave-based execution and non-prod rehearsal.

# 7. Decision Scenarios

| Scenario | Description | Pros | Cons | Best Fit |
|---|---|---|---|---|
| S1 Replatform to Azure fast-track | Move EKS workloads and core services to AKS + Service Bus + Blob with phased waves | Strong enterprise integration path, broad managed services, established governance patterns | Slightly higher directional run-rate in this footprint, identity and messaging remap effort | Organizations prioritizing Microsoft ecosystem alignment |
| S2 Replatform to GCP fast-track | Move to GKE + Pub/Sub + GCS with phased waves | Competitive directional run-rate, strong Kubernetes operating model, low-friction container platform mapping | Requires cloud ops and security model shift if team is AWS/Azure-heavy | Kubernetes-centric teams optimizing cost/perf balance |
| S3 Dual-target pilot then commit | Pilot one production-adjacent domain on both clouds, then choose single strategic target | Reduces selection regret, validates latency and RPO claims with real workloads | Highest short-term cost and timeline overhead | High-stakes migration with uncertain target fit |

# 8. Recommended Plan 30/60/90

30 days:

- Freeze migration scope and dependency map for all environments.
- Build target landing zone baseline in chosen cloud and define identity model for workload identities.
- Build messaging parity test harness for queue/topic semantics.
- Define SLO baselines for latency-sensitive APIs and DR runbooks.

60 days:

- Migrate one non-prod environment end-to-end including ingress, WAF, messaging, and persistent storage.
- Execute failure drills to validate RTO 4h and RPO 30m assumptions.
- Complete security controls mapping for SOC2 and residency evidence collection.
- Finalize cutover design for DNS, certs, and private connectivity.

90 days:

- Execute production wave 1 for least coupled workload domain.
- Run blue/green or canary cutover with rollback guardrails.
- Complete post-cutover performance tuning and cost optimization cycle.
- Approve wave 2 and wave 3 migration schedule based on measured outcomes.

# 9. Open Questions

- Exact current production throughput and p95 or p99 latency by API path are not found in IaC and are required for firm sizing.
- Actual queue depth and message size distribution by queue are not found in IaC.
- Required audit evidence control set beyond SOC2 baseline is not found in IaC.
- Hard residency requirements for AU are assumed for directional pricing only; no AU environment is present in source tfvars.
- Third-party integration constraints around Rancher, Vault, and Datadog tenancy boundaries need confirmation.
- Current DR test frequency and restore time evidence are not found in IaC.

# 10. Component Diagrams

## AWS Source Component Diagram

~~~mermaid
flowchart LR
  subgraph AWS["AWS accounts per environment"]
    subgraph Edge["Edge and DNS"]
      R53["Route53 zones and records"]
      ALB["Public ALB"]
      WAF["WAFv2 ACL"]
      NLB["Private ingress NLB"]
    end

    subgraph Platform["Container platform"]
      EKS["EKS cluster"]
      Addons["EKS add-ons<br/>CNI CoreDNS KubeProxy EBS CSI"]
      Karp["Karpenter"]
      HelmApps["Helm workloads<br/>HxTS services"]
    end

    subgraph Messaging["Messaging"]
      SNS["SNS topics<br/>request reply"]
      SQS["SQS queues<br/>external and internal"]
    end

    subgraph Storage["Storage and backup"]
      EFS["EFS filesystem"]
      S3P["Velero S3 bucket primary"]
      S3B["Velero S3 bucket backup region"]
    end

    subgraph Security["Identity and secrets"]
      IAM["IAM roles and policies<br/>IRSA and worker policies"]
      KMS["KMS keys and aliases"]
      SM["Secrets Manager"]
      SSM["SSM parameters"]
    end

    subgraph Obs["Observability"]
      CWL["CloudWatch logs"]
      DD["Datadog provider and monitors"]
    end
  end

  R53 --> ALB
  ALB --> WAF
  ALB --> NLB
  NLB --> EKS
  EKS --> Addons
  EKS --> Karp
  EKS --> HelmApps
  HelmApps --> SNS
  SNS --> SQS
  HelmApps --> EFS
  EKS --> EFS
  EKS --> S3P
  S3P --> S3B
  IAM --> EKS
  IAM --> SNS
  IAM --> SQS
  KMS --> SNS
  KMS --> SQS
  KMS --> EFS
  KMS --> S3P
  KMS --> S3B
  SM --> HelmApps
  SSM --> EKS
  WAF --> CWL
  EKS --> DD
~~~

## Azure Target Component Diagram

~~~mermaid
flowchart LR
  subgraph AZ["Azure subscriptions per environment"]
    subgraph EdgeA["Edge and DNS"]
      DNSA["Azure DNS"]
      AAG["Application Gateway"]
      WAFA["Azure WAF"]
      ILBA["Internal Load Balancer"]
    end

    subgraph PlatformA["Container platform"]
      AKS["AKS cluster"]
      AddA["AKS add-ons and CSI"]
      KarpA["Autoscaler stack"]
      AppsA["HxTS workloads on Helm"]
    end

    subgraph MsgA["Messaging"]
      SBT["Service Bus topics"]
      SBQ["Service Bus queues subscriptions"]
    end

    subgraph DataA["Storage and backup"]
      AFS["Azure Files or ANF"]
      BLOBP["Blob storage primary"]
      BLOBB["Blob storage paired region"]
    end

    subgraph SecA["Identity and security"]
      MSI["Managed identities and workload identity"]
      KV["Key Vault keys and secrets"]
      CFG["App configuration"]
    end

    subgraph ObsA["Observability"]
      MON["Azure Monitor and Log Analytics"]
      DDA["Datadog integration"]
    end
  end

  DNSA --> AAG
  AAG --> WAFA
  AAG --> ILBA
  ILBA --> AKS
  AKS --> AddA
  AKS --> KarpA
  AKS --> AppsA
  AppsA --> SBT
  SBT --> SBQ
  AppsA --> AFS
  AKS --> BLOBP
  BLOBP --> BLOBB
  MSI --> AKS
  KV --> AppsA
  KV --> SBT
  KV --> SBQ
  CFG --> AppsA
  WAFA --> MON
  AKS --> MON
  MON --> DDA
~~~

## GCP Target Component Diagram

~~~mermaid
flowchart LR
  subgraph GCP["GCP projects per environment"]
    subgraph EdgeG["Edge and DNS"]
      DNSG["Cloud DNS"]
      GLB["External HTTP S Load Balancer"]
      CArmor["Cloud Armor"]
      ILBG["Internal load balancer"]
    end

    subgraph PlatformG["Container platform"]
      GKE["GKE cluster"]
      AddG["GKE add-ons and CSI"]
      AutoG["Node auto provisioning"]
      AppsG["HxTS workloads on Helm"]
    end

    subgraph MsgG["Messaging"]
      PST["Pub Sub topics"]
      PSS["Pub Sub subscriptions"]
    end

    subgraph DataG["Storage and backup"]
      FSTORE["Filestore"]
      GCSP["Cloud Storage primary"]
      GCSB["Cloud Storage backup region"]
    end

    subgraph SecG["Identity and security"]
      WID["Workload identity federation"]
      CKMS["Cloud KMS"]
      GSM["Secret Manager"]
    end

    subgraph ObsG["Observability"]
      GMON["Cloud Logging and Monitoring"]
      DDG["Datadog integration"]
    end
  end

  DNSG --> GLB
  GLB --> CArmor
  GLB --> ILBG
  ILBG --> GKE
  GKE --> AddG
  GKE --> AutoG
  GKE --> AppsG
  AppsG --> PST
  PST --> PSS
  AppsG --> FSTORE
  GKE --> GCSP
  GCSP --> GCSB
  WID --> GKE
  CKMS --> GCSP
  CKMS --> GCSB
  GSM --> AppsG
  CArmor --> GMON
  GKE --> GMON
  GMON --> DDG
~~~
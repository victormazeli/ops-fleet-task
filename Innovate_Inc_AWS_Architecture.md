# Innovate Inc.  
## AWS Cloud Architecture Design Document
*Version: 1.0.0*  
*Cloud Provider: Amazon Web Services (AWS)*

---

## 1. Introduction

This document describes the **cloud architecture** proposed for **Innovate Inc.**, a startup building a web application consisting of:
- A **Python/Flask REST API** (backend)
- A **React single-page application (SPA)** (frontend)
- A **PostgreSQL database**

The system is designed to:
- Start small and remain **cost-effective**
- **Scale automatically** to millions of users
- Handle **sensitive user data securely**
- Support **frequent deployments** using modern CI/CD practices
- Follow **AWS Well-Architected Framework** best practices
- Follow **GitOps** best practices

This document focuses on *what* is built and *why*, using simple explanations and avoiding unnecessary cloud jargon.

---

## 2. Cloud Environment Structure (AWS Accounts)

### 2.1 Account Strategy

Innovate Inc. will use **two AWS accounts**:

1. **Production Account**
   - Hosts the live application
   - Contains real user data
   - Has stricter access controls

2. **Non-Production Account**
   - Used for development, testing, and UAT
   - Safe place to experiment and validate changes before production

### 2.2 Why this approach

This setup provides:
- **Strong isolation** between live and test systems
- **Clear cost separation** for billing and budgeting
- **Reduced risk**, since mistakes in testing cannot affect production

---

## 3. Network Architecture (VPC Design & Security)

### 3.1 Virtual Private Cloud (VPC)

A **Virtual Private Cloud (VPC)** is Innovate’s private network inside AWS.

Key characteristics:
- Deployed across **3 Availability Zones (AZs)**
- Designed to remain available even if one AZ fails

### 3.2 Subnet Layout

Each Availability Zone contains:
- **Public Subnets** (ALB)
- **Private Subnets** (EKS nodes, databases)

### 3.3 Internet Access Model

Client → AWS ALB → Kubernetes (via Kong) → Application Services

### 3.4 Network Security Controls

- Security Groups with least-privilege rules
- AWS WAF on ALB
- Private-by-default architecture

---

## 4. Identity and Access Management (IAM)

- Least privilege access
- No static credentials in containers
- IAM Roles for Service Accounts (IRSA)

---

## 5. Secrets and Configuration Management

- AWS SSM Parameter Store as source of truth
- kubernetes-external-secrets operator
- Encrypted, versioned, auditable secrets

---

## 6. Compute Platform: Kubernetes on Amazon EKS

- Managed EKS control plane
- innovate-platform namespace
- Baseline 2–3 on-demand nodes
- Karpenter for elastic scaling

---

## 7. Containerization & Deployment

- Multi-stage Docker builds
- Amazon ECR
- GitHub Actions (CI)
- Argo CD (GitOps CD)

---

## 8. Ingress & Traffic Management

Client → ALB (TLS, WAF) → Kong Ingress → Services

---

## 9. DNS & Certificates

- Route 53
- AWS Certificate Manager
- HTTPS everywhere

---

## 10. Database Architecture

- Amazon Aurora (PostgreSQL-compatible)
- Multi-AZ
- Automated backups
- Multi-region disaster recovery

---

## 11. Observability, Monitoring, and Alerting (Datadog)

To operate Innovate Inc.’s platform safely as it scales, we need strong **observability** — meaning we can answer:
- “Is the system healthy right now?”
- “What changed when an issue started?”
- “Where is the bottleneck: load balancer, API, database, or Kubernetes?”
- “Are users seeing errors or slow performance?”

Innovate Inc. will use **Datadog** as the primary tool for monitoring, dashboards, alerting, logs, and application performance visibility.

---

### 11.1 What we will monitor

**1) Infrastructure & Network**
- ALB metrics (requests, latency, 4xx/5xx errors)
- AWS WAF blocked requests (security visibility)
- Kubernetes node health (CPU, memory, disk pressure)
- Pod health (restarts, crash loops, readiness failures)

**2) Application Health (Frontend + API)**
- API request rate, latency, error rate
- Key endpoints performance (e.g., login, user profile, core workflows)
- Deployment health (did error rate increase after a release?)

**3) Database Health (Aurora PostgreSQL)**
- CPU and memory usage
- Connections, slow queries
- Replication / failover status
- Storage growth (to prevent surprises)

---

### 11.2 Logs (centralized logging)

All important logs are collected into Datadog so developers can troubleshoot quickly:
- Application logs from Flask services
- Kubernetes and container logs
- Ingress/Gateway logs from Kong (useful for API-level troubleshooting)
- AWS load balancer access logs and WAF visibility (where applicable)

This ensures we have a single place to search logs when something goes wrong.

---

### 11.3 Tracing and performance (APM)

Datadog APM will be enabled for the Flask API to provide:
- End-to-end tracing (which call is slow and why)
- Visibility into downstream dependencies (database calls, external API calls)
- Release impact tracking (did performance degrade after deployment?)

This becomes critical as traffic grows and performance issues become harder to diagnose.

---

### 11.4 Dashboards and alerting

We will create dashboards and alerts that focus on user experience and reliability:

**Alerts (examples)**
- High API error rate (5xx)
- Elevated latency over a sustained period
- Pod crash loops / restart storms
- Kubernetes node shortages (capacity issues)
- Aurora CPU/connection saturation
- DR health signals (so failover readiness is visible)

Alerts are sent to the team’s chosen channels (e.g., email, Slack).

---

### 11.5 Kubernetes integration approach

Datadog is integrated into EKS using:
- A Datadog agent deployed as a Kubernetes component (collects metrics/logs/traces)
- Standard tagging (environment, service name, version) so we can filter dashboards by:
  - Production vs Non-production
  - API vs Frontend
  - Release version (to correlate issues with deployments)



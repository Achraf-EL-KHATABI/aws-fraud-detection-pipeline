# 🛡️ AWS Fraud Detection Pipeline

> Serverless batch ETL pipeline on AWS for credit card fraud detection.
> Built with Terraform, AWS Glue (PySpark), Athena, Step Functions, and QuickSight.

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-7B42BC?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-eu--west--3-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python)](https://www.python.org/)
[![CI](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions)](https://github.com/features/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📖 Overview

This project demonstrates a production-grade, serverless **batch ETL pipeline** on AWS that:

1. Ingests daily credit card transactions into a partitioned S3 data lake
2. Transforms and scores transactions through a PySpark Glue job applying fraud detection rules
3. Catalogs the curated data with AWS Glue Data Catalog
4. Exposes analytics-ready views via Amazon Athena
5. Visualizes fraud KPIs through an Amazon QuickSight dashboard
6. Orchestrates the whole flow with Step Functions + EventBridge (daily schedule)
7. Monitors execution with CloudWatch alarms and SNS notifications

The entire infrastructure is deployed via **Terraform** with a **GitHub Actions CI/CD pipeline** using **OIDC authentication** (zero static AWS credentials).

---

## 🏗️ Architecture

```
┌─────────────┐   ┌──────────┐   ┌────────────┐   ┌─────────┐   ┌────────────┐
│  Dataset    │──▶│   S3     │──▶│   Glue     │──▶│ Athena  │──▶│ QuickSight │
│  (Kaggle)   │   │  raw/    │   │  PySpark   │   │  (SQL   │   │ (dashboard │
│             │   │  curated/│   │  ETL job   │   │  views) │   │  fraude)   │
└─────────────┘   └──────────┘   └────────────┘   └─────────┘   └────────────┘
                       │                ▲
                       ▼                │
                  ┌─────────────────────┘
                  │ EventBridge cron ──▶ Step Functions ──▶ orchestration
                  │
                  ▼
            CloudWatch Logs + SNS alerting
```

---

## 🛠️ Tech Stack

| Layer | Service / Tool |
|---|---|
| **Storage** | Amazon S3 (3-zone medallion: raw / curated / analytics) |
| **Processing** | AWS Glue 4.0 (PySpark) |
| **Catalog** | AWS Glue Data Catalog + Crawler |
| **Query** | Amazon Athena |
| **Orchestration** | AWS Step Functions + Amazon EventBridge |
| **Monitoring** | Amazon CloudWatch + Amazon SNS |
| **Visualization** | Amazon QuickSight |
| **IaC** | Terraform 1.6+ |
| **CI/CD** | GitHub Actions (OIDC, no static credentials) |
| **Security** | KMS encryption, least-privilege IAM, S3 block public access |

---

## 📁 Repository Structure

```
aws-fraud-detection-pipeline/
├── .github/workflows/        # CI/CD pipelines (Terraform + Python)
├── terraform/                # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   └── modules/
│       ├── s3-datalake/
│       ├── glue/
│       ├── stepfunctions/
│       ├── eventbridge/
│       └── monitoring/
├── glue_jobs/                # PySpark ETL scripts
├── athena/queries/           # Analytics SQL views
├── scripts/                  # Helper scripts (data upload, bootstrap)
├── docs/                     # Architecture diagrams, screenshots
└── README.md
```

---

## 🚀 Getting Started

> 🚧 **Work in progress** — Setup instructions will be completed as the project is built.

### Prerequisites

- AWS account with admin access
- Terraform 1.6+
- AWS CLI v2 configured with a named profile
- Python 3.10+
- GitHub account

### Quick start

```bash
git clone https://github.com/Achraf-EL-KHATABI/aws-fraud-detection-pipeline.git
cd aws-fraud-detection-pipeline
# Detailed setup steps will be added once Terraform is in place
```

---

## 📊 Dataset

This pipeline processes the **[Credit Card Fraud Detection](https://www.kaggle.com/datasets/mlg-ulb/creditcardfraud)** dataset from Kaggle:
- 284,807 transactions made by European cardholders (September 2013)
- 492 labeled fraud cases (highly imbalanced — 0.172% fraud rate)
- Features anonymized via PCA transformation (V1–V28) + `Time`, `Amount`, `Class`

---

## 🎯 Fraud Detection Rules

The Glue job applies a composite scoring approach combining:

1. **Amount anomaly** — transaction > 3× rolling 30-day customer average
2. **Velocity** — > 5 transactions per hour from the same account
3. **Geographic impossibility** — 2 transactions > 500 km apart within 1 hour
4. **Suspicious time window** — high-value transactions between 02:00–05:00 local time
5. **Composite risk score** — weighted aggregation → `HIGH` / `MEDIUM` / `LOW` flag

---

## 💰 Cost Estimate

Designed to fit within the AWS Free Tier for development:
- **S3 / Glue / Athena / Step Functions / EventBridge / CloudWatch** → < €1 / month at demo scale
- **QuickSight Author** → €24 / month (use 30-day free trial for the demo)

A monthly budget alert at €5 is recommended.

---

## 👤 Author

**Achraf EL KHATABI** — Data & Cloud Engineer
🔗 [LinkedIn](https://www.linkedin.com/in/achraf-el-khatabi) · [GitHub](https://github.com/Achraf-EL-KHATABI)

---

## 📜 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

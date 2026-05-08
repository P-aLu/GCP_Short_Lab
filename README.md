# Google Cloud Training Lab

A collection of hands-on, infrastructure-as-code GCP labs. Each lab deploys a real cloud environment to practice against and can be torn down in a single command when you are done.

Labs are independent — deploy one or all of them at the same time.

---

## What is this?

This repo provides self-contained GCP environments for learning cloud security, infrastructure, and operations. Each lab folder under `labs/` is a standalone Terraform root that provisions a realistic (and sometimes intentionally vulnerable) GCP setup.

| Lab | Title | Type |
|-----|-------|------|
| `lab-01-gsc-privesc` | GCP Privilege Escalation via Stolen SA Key | Security / CTF |

Full lab status and build progress: [`docs/labs/README.md`](docs/labs/README.md)

---

## Requirements

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Terraform | ≥ 1.6 | [terraform.io/downloads](https://developer.hashicorp.com/terraform/install) |
| gcloud CLI | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |

### GCP accounts and permissions

You need **two** things on the GCP side:

**1. A GCP project** where the lab resources will be deployed.
Your user account (or a service account) must have these roles on that project:

| Role | Why it is needed |
|------|----------------|
| `Editor` (or a custom role) | Create compute, storage, SQL, IAM, and Cloud Function resources |
| `Storage Admin` | Create and write the remote-state bucket |
| `Service Account Admin` | Create per-lab service accounts |
| `Security Admin` | Bind IAM policies to the lab service accounts |

> For security labs that involve a second GCP project (e.g. `lab-01-gsc-privesc`), you need the same permissions on that second project too.

**2. A GCS bucket for Terraform remote state** — one bucket shared across all labs, with each lab writing to its own prefix. See [Create the state bucket](#2--create-the-remote-state-bucket) below.

---

## Quickstart

### 1 — Authenticate

```bash
gcloud auth application-default login
gcloud config set project <PROJECT_ID>
```

### 2 — Create the remote-state bucket

Run this once per GCP project. The bucket name must be globally unique.

```bash
gcloud storage buckets create gs://<YOUR_STATE_BUCKET> \
  --project=<PROJECT_ID> \
  --location=<REGION> \
  --uniform-bucket-level-access
```

### 3 — Configure your variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in:

```hcl
project_id   = "<PROJECT_ID>"
region       = "europe-west1"
state_bucket = "<YOUR_STATE_BUCKET>"
owner        = "<your-name>"
```

> `terraform.tfvars` is git-ignored. Never commit it.

### 4 — Deploy

**A single lab:**

```bash
./scripts/lab.sh apply lab-01-gsc-privesc
```

**Every lab at once:**

```bash
./scripts/all-labs.sh apply
```

### 5 — Tear down

**A single lab:**

```bash
./scripts/lab.sh destroy lab-01-gsc-privesc
```

**Everything:**

```bash
./scripts/all-labs.sh destroy
```

> Always destroy resources when you are done with a session to avoid unexpected GCP charges.

---

## Repository layout

```
.
├── README.md
├── CLAUDE.md                     # Guidance for Claude Code
├── terraform.tfvars.example      # Variable template — copy and fill in
├── docs/
│   ├── deployment.md             # Full deployment reference
│   ├── labs/
│   │   └── README.md             # Lab tracker (status, kill chains)
│   ├── architecture.md           # Module design and conventions
│   ├── conventions.md            # Naming, labelling, Terraform style
│   ├── cost-controls.md          # Per-service cost guidance
│   └── gcp-auth.md               # Auth and service account troubleshooting
├── modules/                      # Reusable Terraform modules
│   ├── network/
│   ├── compute/
│   ├── iam/
│   └── ...
├── labs/                         # One folder per lab — each is a Terraform root
│   ├── lab-01-gsc-privesc/
│   └── ...
└── scripts/
    ├── lab.sh                    # Deploy / destroy a single lab
    └── all-labs.sh               # Deploy / destroy all labs in order
```

---

## Lab types

**Security / CTF labs** deploy a vulnerable-by-design environment. The learner is given a starting foothold (e.g. a stolen service account key) and must follow the intended kill chain to reach the final flag. No prior access to the environment is needed beyond the initial credential.

**Infrastructure labs** *(planned)* have the learner build and configure GCP services themselves, following guided steps in the lab README.

---

## Cost

All labs default to the smallest viable machine types (`e2-micro`, `e2-small`) and standard persistent disks to keep costs low. Estimated cost per lab while running is under $1/day for most scenarios.

**Always run `destroy` at the end of a session.** Leaving resources up overnight is the main source of unexpected charges.

---

## Further reading

| Document | Contents |
|----------|----------|
| [`docs/deployment.md`](docs/deployment.md) | Full deployment guide, skip flags, state layout, troubleshooting |
| [`docs/labs/README.md`](docs/labs/README.md) | Lab tracker, per-lab kill chains, build status |
| [`CLAUDE.md`](CLAUDE.md) | IaC conventions, toolchain, instructions for Claude Code |

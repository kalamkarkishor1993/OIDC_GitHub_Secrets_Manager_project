# Keyless AWS CI/CD with GitHub Actions OIDC

A production-style CI/CD pipeline that deploys AWS infrastructure via Terraform **without storing any long-lived AWS credentials** in GitHub. Authentication uses OpenID Connect (OIDC) federation between GitHub Actions and AWS IAM, and application secrets are managed through AWS Secrets Manager.

## Architecture

```
GitHub Actions (push to main)
        │
        │  OIDC token (short-lived JWT)
        ▼
AWS STS — AssumeRoleWithWebIdentity
        │
        │  Temporary credentials (~1 hour)
        ▼
IAM Role: TerraformGitHubRole (least-privilege)
        │
        ├──► Terraform (S3 remote backend for shared state)
        │        │
        │        └──► Provisions AWS infrastructure
        │
        └──► AWS Secrets Manager
                 └──► Application secrets fetched at runtime
```

## Why this approach

Traditional CI/CD pipelines store an AWS Access Key + Secret Key as GitHub Secrets. These are long-lived — if leaked, they remain valid until manually rotated. This project instead uses OIDC: GitHub issues a short-lived identity token on every workflow run, AWS verifies it against a trust policy scoped to this exact repository and branch, and issues temporary credentials that expire automatically. No AWS key ever exists in GitHub, on disk, or in logs.

## What's in this repo

| File | Purpose |
|---|---|
| `main.tf` | Terraform provider config + S3 remote backend |
| `oidc.tf` | OIDC identity provider reference, IAM role, trust policy, least-privilege IAM policies |
| `secrets.tf` | AWS Secrets Manager secret + IAM policy to read it |
| `variables.tf` | Input variables (e.g., `db_password`, marked sensitive) |
| `.github/workflows/terraform.yml` | CI/CD pipeline: assumes role via OIDC, runs `terraform plan`/`apply` |

## Setup

1. **Bootstrap (one-time, from a trusted machine with your own AWS credentials):**
   ```bash
   terraform init
   terraform apply
   ```
   This creates the OIDC provider reference, the IAM role, and its trust policy — GitHub Actions can't create its own role on the first run, so this step is done manually once.

2. **GitHub repo secrets required:**
   - `AWS_ROLE_ARN` — ARN of the created `TerraformGitHubRole`
   - `AWS_REGION` — e.g., `ap-south-1`
   - `DB_PASSWORD` — passed to Terraform as `TF_VAR_db_password`, used to seed the Secrets Manager secret

3. **Push to `main`** — the workflow assumes the IAM role via OIDC and runs Terraform automatically.

## Debugging journey

This pipeline didn't work end-to-end on the first attempt. Documenting the real issues here because working through them is a big part of what this project demonstrates.

**1. `Not authorized to perform sts:AssumeRoleWithWebIdentity`**
The IAM trust policy's `sub` condition looked correct (`repo:owner/repo:*`), but the role assumption still failed. Root-caused it using **AWS CloudTrail** rather than guessing — the actual `sub` claim GitHub sent was `repo:owner@ownerID/repo@repoID:ref:refs/heads/main`. GitHub appends numeric owner/repo IDs to the claim when a repository has been deleted and recreated (which had happened here). Fixed by wildcarding the IDs in the trust policy: `repo:owner@*/repo@*:ref:refs/heads/main`.

**2. Terraform trying to recreate resources that already existed**
After fixing the trust policy, `terraform apply` in CI kept trying to create the IAM role and secret from scratch, failing with `EntityAlreadyExists`. Cause: Terraform state was only stored locally — the CI runner had no visibility into what had already been provisioned. Fixed by migrating to an **S3 remote backend**, giving local and CI environments a single shared state.

**3. Iterative least-privilege permission gaps**
Once state was shared, several narrow `AccessDenied` errors surfaced one at a time as the pipeline exercised different AWS APIs: `iam:ListOpenIDConnectProviders`, `iam:GetRole`, `secretsmanager:GetSecretValue`. Rather than attaching a broad admin policy, each gap was closed with a scoped inline policy limited to the specific actions and resources actually needed.

## Security notes

- No AWS access keys are stored anywhere in this repository or in GitHub Secrets.
- `sensitive = true` on the `db_password` variable prevents it from appearing in Terraform plan/apply output — though it is still present in the state file, which is why remote state should always be encrypted at rest.
- `::add-mask::` is used in the workflow to prevent secrets from appearing in Actions logs.
- The IAM trust policy is scoped to a specific repository and branch (`ref:refs/heads/main`), not the whole GitHub account.

## Possible next steps

- Split workflow into `plan` (on pull request) and `apply` (on merge to main)
- Separate state/environments for dev and prod
- Automatic secret rotation via a Secrets Manager rotation Lambda

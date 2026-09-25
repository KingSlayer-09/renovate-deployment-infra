# Terraform live environments on AWS

This learning project deploys **dev**, **stage**, and **prod** as separate Terraform states and separate AWS resource sets. Each environment has a VPC across two Availability Zones, a public application load balancer, one ECS Fargate service pulling a Python image from ECR, an S3 data bucket, a Secrets Manager secret, and an HTTP API Gateway route backed by Lambda.

The container answers `/` and `/health` on port 8080. The API answers `GET /hello`. Lambda reports whether a version has been added to the secret, but never returns its value.

## Layout

```text
app/                         Python HTTP app and Dockerfile
infra/bootstrap/             State bucket, three ECR repos, GitHub OIDC roles
infra/modules/app_stack/     Shared environment infrastructure
infra/live/{dev,stage,prod}/ Thin roots with separate state keys and settings
.github/workflows/deploy.yml Branch-based GitHub Actions deployment
```

## Prerequisites

- A **dedicated learning AWS account** with permissions to run the bootstrap stack. Bootstrap stores local Terraform state on your machine; keep that state safe and backed up. Do not commit it.
- Terraform >= 1.10, AWS CLI, Docker for local runs, and a GitHub repository with a `main` branch.
- AWS charges for the load balancers, Fargate tasks, CloudWatch, and other resources while they run. There is no NAT gateway in this example; Fargate tasks receive public IPs for ECR and CloudWatch access, while their security group accepts traffic only from the load balancer. The sample load balancer uses HTTP; configure a domain, ACM certificate, HTTPS listener, WAF, and tighter IAM permissions before using this pattern for real production traffic.

## 1. Bootstrap the AWS account

Edit `infra/bootstrap/terraform.tfvars.example` and save it as `infra/bootstrap/terraform.tfvars`. Set your GitHub `owner/name`. For repositories created on or after **15 July 2026**, supply the numeric GitHub owner and repository IDs. Find them through the GitHub API or repository settings. For older repositories using the legacy OIDC subject format, set both IDs to empty strings. The IAM trust policy matches the chosen repository and each GitHub Environment exactly.

In PowerShell:

```powershell
cd infra/bootstrap
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output
```

The bootstrap creates:

- A versioned, encrypted S3 state bucket using S3 lockfiles.
- An ECR repository for each environment, with immutable image tags and a 30-image retention policy.
- A GitHub OIDC provider and one deployment role per environment.

The deployment roles use `PowerUserAccess` plus project-role IAM permissions so the example can create its resources. This is broad access. Use a dedicated learning account; scope permissions further and use separate AWS accounts for environments in a real production setup. If your account already has the GitHub OIDC provider, import it into bootstrap state before applying.

## 2. Configure GitHub Environments

Create GitHub Environments named `dev`, `stage`, and `prod`. Under each environment, add these **variables** using the corresponding bootstrap outputs:

| Variable | Example for dev |
| --- | --- |
| `AWS_ROLE_ARN` | `github_role_arns.dev` output |
| `AWS_REGION` | `us-east-1` |
| `TF_STATE_BUCKET` | `state_bucket` output |
| `ECR_REPOSITORY` | `tf-live-demo/dev/app` |

Set each GitHub Environment's selected deployment branch rule to its matching branch: `dev` → `feature/dev`, `stage` → `feature/stage`, and `prod` → `main`. Add required reviewers for `prod` (and `stage` if desired). Both the plan and deploy jobs reference the environment, so protected environments require approval at both jobs. AWS authentication uses GitHub OIDC; no long-lived AWS access keys are stored in GitHub.

If you change `project_name` or `aws_region`, update bootstrap inputs, all three `infra/live/*/terraform.tfvars` files, and the GitHub environment variables together.

## 3. Deploy

Push to `feature/dev`, `feature/stage`, or `main` to deploy `dev`, `stage`, or `prod`, respectively. The workflow has three dependent jobs: TruffleHog scans the branch history for secrets; Terraform checks formatting, validates, and makes a speculative plan for that branch's environment; then a dynamic deployment matrix selects that environment, builds and pushes an immutable SHA-based image to its ECR repository, makes a fresh saved plan, and applies it. A failed scan or plan prevents deployment. The final job plans again because it runs on a separate runner after the image push. Deployments to the same environment are serialized across workflow runs. You can also use **Actions → Scan, plan, and deploy Terraform → Run workflow** on one of these branches.

For a local Terraform plan, build and push an image to the bootstrapped ECR repository first, then initialize the desired environment with its state bucket:

```powershell
cd infra/live/dev
terraform init -backend-config="bucket=YOUR_STATE_BUCKET" -backend-config="region=us-east-1"
terraform plan -var="image_tag=YOUR_EXISTING_ECR_TAG"
```

The three live roots intentionally use different CIDR ranges and state keys. The production example runs one ECS **service** with two tasks. Add HTTPS and private networking for a more resilient production deployment.

## Try the endpoints

```powershell
curl.exe (terraform output -raw api_url)
curl.exe (terraform output -raw ecs_url)
```

The secret is created without a value. To see the Lambda response change from `secret_configured: false` to `true`, add a value manually in Secrets Manager or with `aws secretsmanager put-secret-value --secret-id SECRET_ARN --secret-string '{"example":"value"}'`. Avoid placing real secret values in Terraform state.

## Cleanup

Destroy each live environment before destroying bootstrap. The data bucket is configured with `force_destroy = false`, so empty it first if you put objects in it. ECR repositories likewise must be empty before bootstrap destroy. Removing the bootstrap state bucket also requires emptying its versioned objects and lockfiles; preserve a copy of state until the cleanup is complete.

```powershell
cd infra/live/dev
terraform destroy -var="image_tag=YOUR_EXISTING_ECR_TAG"
```

Repeat for stage and prod, then destroy `infra/bootstrap` using its local state.

## Notes

- The GitHub workflow applies changes after planning. GitHub Environment reviewers are the approval gate for protected environments.
- S3 state has versioning, encryption, public access blocking, and native Terraform lockfiles. [Terraform S3 backend guidance](https://developer.hashicorp.com/terraform/language/backend/s3).
- GitHub OIDC subject format changed for newer repositories. [GitHub OIDC reference](https://docs.github.com/en/actions/reference/security/oidc) and [AWS credentials action](https://github.com/aws-actions/configure-aws-credentials).

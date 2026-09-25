data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  environments = toset(["dev", "stage", "prod"])
  state_bucket = "${var.project_name}-state-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  repo_parts   = split("/", var.github_repository)
  oidc_repo    = var.github_owner_id == "" ? var.github_repository : "${local.repo_parts[0]}@${var.github_owner_id}/${local.repo_parts[1]}@${var.github_repo_id}"
}

resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_ecr_repository" "app" {
  for_each             = local.environments
  name                 = "${var.project_name}/${each.key}/app"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  force_delete = false
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = local.environments
  repository = aws_ecr_repository.app[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the newest 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  for_each = local.environments
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.oidc_repo}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "github" {
  for_each           = local.environments
  name               = "${var.project_name}-${each.key}-github"
  assume_role_policy = data.aws_iam_policy_document.github_trust[each.key].json
}

# A dedicated learning account is required. Narrow this policy before using it in a shared account.
resource "aws_iam_role_policy_attachment" "github_power_user" {
  for_each   = local.environments
  role       = aws_iam_role.github[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "github_iam" {
  for_each = local.environments
  statement {
    sid = "ManageProjectRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:PutRolePolicy", "iam:GetRolePolicy",
      "iam:DeleteRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-ecs-execution",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-lambda"
    ]
  }
  statement {
    sid       = "AttachExecutionPolicy"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-ecs-execution"]
    condition {
      test     = "StringEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
    }
  }
  statement {
    sid     = "PassProjectRolesToServices"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-ecs-execution",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${each.key}-lambda"
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_iam" {
  for_each = local.environments
  name     = "${var.project_name}-manage-roles"
  role     = aws_iam_role.github[each.key].id
  policy   = data.aws_iam_policy_document.github_iam[each.key].json
}

data "aws_iam_policy_document" "github_state" {
  for_each = local.environments
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.key}/*"]
    }
  }
  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/${each.key}/terraform.tfstate",
      "${aws_s3_bucket.state.arn}/${each.key}/terraform.tfstate.tflock"
    ]
  }
}

resource "aws_iam_role_policy" "github_state" {
  for_each = local.environments
  name     = "${var.project_name}-state"
  role     = aws_iam_role.github[each.key].id
  policy   = data.aws_iam_policy_document.github_state[each.key].json
}

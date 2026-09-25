output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "github_role_arns" {
  value = { for env, role in aws_iam_role.github : env => role.arn }
}

output "ecr_repository_urls" {
  value = { for env, repo in aws_ecr_repository.app : env => repo.repository_url }
}


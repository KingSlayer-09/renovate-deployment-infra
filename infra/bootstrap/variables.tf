variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "tf-live-demo"
}

variable "github_repository" {
  description = "GitHub repository in owner/name form."
  type        = string
  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "Use owner/name, for example octocat/terraform-live-demo."
  }
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID for repositories using immutable OIDC subjects; leave empty for legacy subjects."
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID for repositories using immutable OIDC subjects; leave empty for legacy subjects."
  type        = string
  default     = ""
  validation {
    condition     = (var.github_owner_id == "") == (var.github_repo_id == "")
    error_message = "Set both github_owner_id and github_repo_id, or neither."
  }
}

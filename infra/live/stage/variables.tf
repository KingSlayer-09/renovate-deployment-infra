variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "tf-live-demo"
}

variable "vpc_cidr" { type = string }
variable "ecs_desired_count" { type = number }
variable "log_retention_days" { type = number }

variable "image_tag" {
  description = "Immutable ECR image tag built by the deployment workflow."
  type        = string
}

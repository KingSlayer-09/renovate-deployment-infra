variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "image_tag" { type = string }
variable "ecs_desired_count" { type = number }
variable "log_retention_days" { type = number }


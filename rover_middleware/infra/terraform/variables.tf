variable "aws_region" {
  description = "AWS region for Rover staging."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix."
  type        = string
  default     = "rover"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "staging"
}

variable "allowed_origins" {
  description = "HTTPS origins allowed to call the staging API."
  type        = list(string)
}

variable "container_image" {
  description = "Rover API container image URI."
  type        = string
}

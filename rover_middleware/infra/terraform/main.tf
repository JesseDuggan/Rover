provider "aws" {
  region = var.aws_region
}

locals {
  name = "${var.project_name}-${var.environment}"
}

resource "aws_cognito_user_pool" "rover" {
  name = "${local.name}-users"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "flutter" {
  name                                 = "${local.name}-flutter"
  user_pool_id                         = aws_cognito_user_pool.rover.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["rover://auth/callback"]
  logout_urls                          = ["rover://auth/logout"]
}

resource "aws_secretsmanager_secret" "api_database" {
  name = "${local.name}/api/database"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/ecs/${local.name}-api"
  retention_in_days = 30
}

# Network, ECS Fargate service, ALB, RDS PostgreSQL/PostGIS parameterization,
# Secrets Manager wiring, alarms, and migration runner are intentionally
# completed during the AWS credentialed deployment pass. This file establishes
# the repeatable Terraform root and identity resources without hardcoded secrets.

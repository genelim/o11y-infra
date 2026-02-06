terraform {
  required_providers {
    signalfx = {
      source  = "splunk-terraform/signalfx"
      version = "~> 6.14"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "signalfx" {
  auth_token = var.splunk_o11y_token
  api_url    = var.splunk_o11y_api_url
}

provider "aws" {
  region = var.aws_region
}

variable "splunk_o11y_token" {
  type      = string
  sensitive = true
}

variable "splunk_o11y_api_url" {
  type = string
}

variable "account_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "obs_tier" {
  type    = string
  default = "bronze"
}

locals {
  is_silver_plus = contains(["silver", "gold", "platinum"], var.obs_tier)
  is_gold_plus   = contains(["gold", "platinum"], var.obs_tier)
  is_platinum    = var.obs_tier == "platinum"
}

# You can either:
# - hard-code values again here, or
# - pass them in as variables/remote state from module A.
# For simplicity, assume we pass in role ARN and external integration id:

variable "external_integration_id" {
  type = string
}

variable "external_integration_external_id" {
  type = string
}

variable "splunk_role_arn" {
  type = string
}

# --------- Splunk AWS integration ---------

resource "signalfx_aws_integration" "this" {
  enabled                 = true
  integration_id          = var.external_integration_id
  external_id             = var.external_integration_external_id
  role_arn                = var.splunk_role_arn

  regions                 = [var.aws_region]
  import_cloud_watch      = true
  use_metric_streams_sync = true
  enable_aws_usage        = true
}

# --------- Splunk O11y dashboards ---------

resource "signalfx_dashboard_group" "aws_account" {
  name = "${var.account_name} - AWS"
}

# Bronze core charts...

resource "signalfx_time_chart" "elb_request_count" { ... }
resource "signalfx_time_chart" "elb_5xx_error_rate" { ... }
resource "signalfx_time_chart" "rds_cpu" { ... }

resource "signalfx_dashboard" "aws_core_metrics" { ... }

# Platinum app_overview as you already have...
resource "signalfx_time_chart" "elb_request_count_platinum" { ... }
resource "signalfx_time_chart" "elb_5xx_error_rate_platinum" { ... }
resource "signalfx_dashboard" "app_overview" { ... }


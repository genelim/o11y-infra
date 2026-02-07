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

# --------- Providers ---------

provider "signalfx" {
  auth_token = var.splunk_o11y_token
  api_url    = var.splunk_o11y_api_url
}

provider "aws" {
  region = var.aws_region
}

# --------- Variables ---------

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
  default = "bronze"  # allowed: "bronze", "silver", "gold", "platinum"
}

# values passed from tf-aws-splunk-base
variable "external_integration_id" {
  type = string
}

variable "external_integration_external_id" {
  type = string
}

variable "splunk_role_arn" {
  type = string
}

locals {
  # Bronze = minimal
  is_silver_plus = contains(["silver", "gold", "platinum"], var.obs_tier)
  is_gold_plus   = contains(["gold", "platinum"], var.obs_tier)
  is_platinum    = var.obs_tier == "platinum"
}

# --------- Splunk AWS integration ---------


resource "signalfx_aws_integration" "this" {
  enabled                 = true
  # REMOVE this line:
   integration_id        = var.external_integration_id

  external_id             = var.external_integration_external_id
  role_arn                = var.splunk_role_arn

  regions                 = [var.aws_region]
  import_cloud_watch      = true
  enable_aws_usage        = true

  poll_rate               = 60
  use_metric_streams_sync = false
}


# --------- Splunk O11y dashboards ---------

resource "signalfx_dashboard_group" "aws_account" {
  name = "${var.account_name} - AWS"
}

# ----- Bronze core charts -----

resource "signalfx_time_chart" "elb_request_count" {
  name        = "${var.account_name} - ELB/ALB Request Count"
  description = "Sum of request count across ELB/ALB in ${var.aws_region}."
  plot_type   = "LineChart"

  program_text = <<-EOT
    data("aws.elb.request_count",
         filter=filter("aws_region", "${var.aws_region}"),
         rollup="sum").publish()
  EOT
}

resource "signalfx_time_chart" "elb_5xx_error_rate" {
  name        = "${var.account_name} - ELB/ALB 5xx Error Rate"
  description = "Percent of 5xx responses on ELB/ALB in ${var.aws_region}."

  program_text = <<-EOF
    errors = data("aws.elb.httpcode_elb_5xx",
                  filter=filter("aws_region", "${var.aws_region}"),
                  rollup="sum")
    requests = data("aws.elb.request_count",
                    filter=filter("aws_region", "${var.aws_region}"),
                    rollup="sum")
    (errors / requests).scale(100).publish(label="error_rate_pct")
  EOF
}

resource "signalfx_time_chart" "rds_cpu" {
  name        = "${var.account_name} - RDS CPU Utilization"
  description = "Average CPU for RDS instances in ${var.aws_region}."
  plot_type   = "LineChart"

  program_text = <<-EOT
    data("aws.rds.cpuutilization",
         filter=filter("aws_region", "${var.aws_region}"),
         rollup="average").publish()
  EOT
}

resource "signalfx_dashboard" "aws_core_metrics" {
  name            = "${var.account_name} - Core AWS Metrics"
  dashboard_group = signalfx_dashboard_group.aws_account.id
  description     = "Core AWS infra metrics for ${var.account_name}."
  time_range      = "-1h"

  chart {
    chart_id = signalfx_time_chart.elb_request_count.id
    width    = 12
    height   = 4
    row      = 0
    column   = 0
  }

  chart {
    chart_id = signalfx_time_chart.elb_5xx_error_rate.id
    width    = 12
    height   = 4
    row      = 4
    column   = 0
  }

  chart {
    chart_id = signalfx_time_chart.rds_cpu.id
    width    = 12
    height   = 4
    row      = 8
    column   = 0
  }
}

# ----- Platinum-only App Overview (no chart ID reuse) -----

resource "signalfx_time_chart" "elb_request_count_platinum" {
  count       = local.is_platinum ? 1 : 0
  name        = "${var.account_name} - ELB Requests (Platinum)"
  description = "ELB/ALB request count for Platinum tier app overview."
  plot_type   = "LineChart"

  program_text = <<-EOT
    data("aws.elb.request_count",
         filter=filter("aws_region", "${var.aws_region}"),
         rollup="sum").publish()
  EOT
}

resource "signalfx_time_chart" "elb_5xx_error_rate_platinum" {
  count       = local.is_platinum ? 1 : 0
  name        = "${var.account_name} - ELB 5xx Error Rate (Platinum)"
  description = "ELB/ALB 5xx error rate for Platinum tier app overview."

  program_text = <<-EOF
    errors = data("aws.elb.httpcode_elb_5xx",
                  filter=filter("aws_region", "${var.aws_region}"),
                  rollup="sum")
    requests = data("aws.elb.request_count",
                    filter=filter("aws_region", "${var.aws_region}"),
                    rollup="sum")
    (errors / requests).scale(100).publish(label="error_rate_pct")
  EOF
}

resource "signalfx_dashboard" "app_overview" {
  count           = local.is_platinum ? 1 : 0
  name            = "${var.account_name} - App Overview"
  dashboard_group = signalfx_dashboard_group.aws_account.id
  description     = "Higher-tier app overview for ${var.account_name}."
  time_range      = "-1h"

  chart {
    chart_id = signalfx_time_chart.elb_request_count_platinum[0].id
    width    = 12
    height   = 4
    row      = 0
    column   = 0
  }

  chart {
    chart_id = signalfx_time_chart.elb_5xx_error_rate_platinum[0].id
    width    = 12
    height   = 4
    row      = 4
    column   = 0
  }
}


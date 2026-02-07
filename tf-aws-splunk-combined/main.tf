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

variable "enable_rds"    { type = bool, default = false }
variable "enable_lambda" { type = bool, default = false }
variable "enable_s3"     { type = bool, default = false }

locals {
  has_rds    = var.enable_rds
  has_lambda = var.enable_lambda
  has_s3     = var.enable_s3
  has_elb    = true 
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

#Bronze
# 1) ELB/ALB request count (by load balancer)
resource "signalfx_time_chart" "elb_request_count" {
  count       = local.has_elb ? 1 : 0
  name        = "${var.account_name} - ELB/ALB Request Count"
  description = "Sum of request count across ELB/ALB in ${var.aws_region}."
  plot_type   = "LineChart"

  program_text = <<-EOT
    data("RequestCount",
         filter=(filter("namespace", "AWS/ApplicationELB")
                 or filter("namespace", "AWS/ELB"))
           and filter("aws_region", "${var.aws_region}")
        ).sum(by=["aws_account_id", "aws_region", "LoadBalancer"]).publish()
  EOT
}

# 2) ELB/ALB 5xx error rate (percent)
resource "signalfx_time_chart" "elb_5xx_error_rate" {
  count       = local.has_elb ? 1 : 0
  name        = "${var.account_name} - ELB/ALB 5xx Error Rate"
  description = "Percent of 5xx responses on ELB/ALB in ${var.aws_region}."

  program_text = <<-EOF
    errors = data("HTTPCode_ELB_5XX_Count",
                  filter=(filter("namespace", "AWS/ApplicationELB")
                          or filter("namespace", "AWS/ELB"))
                    and filter("aws_region", "${var.aws_region}")
                 ).sum(by=["aws_account_id", "aws_region", "LoadBalancer"])
    requests = data("RequestCount",
                    filter=(filter("namespace", "AWS/ApplicationELB")
                            or filter("namespace", "AWS/ELB"))
                      and filter("aws_region", "${var.aws_region}")
                   ).sum(by=["aws_account_id", "aws_region", "LoadBalancer"])
    (errors / requests).scale(100).publish(label="error_rate_pct")
  EOF
}

# 3) RDS CPU usage (by DB instance)
resource "signalfx_time_chart" "rds_cpu" {
  count       = local.has_rds ? 1 : 0
  name        = "${var.account_name} - RDS CPU Utilization"
  description = "Average CPU for RDS instances in ${var.aws_region}."
  plot_type   = "LineChart"

  program_text = <<-EOT
    data("CPUUtilization",
         filter=filter("namespace", "AWS/RDS")
           and filter("aws_region", "${var.aws_region}")
        ).mean(by=["aws_account_id", "aws_region", "DBInstanceIdentifier"]).publish()
  EOT
}



resource "signalfx_dashboard" "aws_core_metrics" {
  name            = "${var.account_name} - Core AWS Metrics"
  dashboard_group = signalfx_dashboard_group.aws_account.id
  time_range      = "-1h"

  # ELB row (only if has_elb)
  dynamic "chart" {
    for_each = local.has_elb ? [1] : []
    content {
      chart_id = signalfx_time_chart.elb_request_count[0].id
      width    = 12
      height   = 4
      row      = 0
      column   = 0
    }
  }

  dynamic "chart" {
    for_each = local.has_elb ? [1] : []
    content {
      chart_id = signalfx_time_chart.elb_5xx_error_rate[0].id
      width    = 12
      height   = 4
      row      = 4
      column   = 0
    }
  }

  # RDS row (only if has_rds)
  dynamic "chart" {
    for_each = local.has_rds ? [1] : []
    content {
      chart_id = signalfx_time_chart.rds_cpu[0].id
      width    = 12
      height   = 4
      row      = 8
      column   = 0
    }
  }
}

# ----- Platinum-only App Overview (no chart ID reuse) -----

resource "signalfx_time_chart" "elb_request_count_platinum" {
  count       = local.is_platinum && local.has_elb ? 1 : 0
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
  count       = local.is_platinum && local.has_elb ? 1 : 0
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

  # ELB request count (only if ELB enabled)
  dynamic "chart" {
    for_each = local.has_elb ? [1] : []
    content {
      chart_id = signalfx_time_chart.elb_request_count_platinum[0].id
      width    = 12
      height   = 4
      row      = 0
      column   = 0
    }
  }

  # ELB 5xx error rate (only if ELB enabled)
  dynamic "chart" {
    for_each = local.has_elb ? [1] : []
    content {
      chart_id = signalfx_time_chart.elb_5xx_error_rate_platinum[0].id
      width    = 12
      height   = 4
      row      = 4
      column   = 0
    }
  }

  # You can add more Platinum-only panels here, gated by locals.has_rds, etc.
}


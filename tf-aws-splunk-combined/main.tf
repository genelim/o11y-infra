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
  # profile = var.aws_profile
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

# variable "aws_profile" {
#   type = string
# }

# --------- Splunk external integration ---------
# Gives us external_id and Splunk's AWS account ID. [web:1][web:90]

resource "signalfx_aws_external_integration" "this" {
  name = var.account_name
}

# --------- IAM role in your AWS account ---------
# Trusts Splunk's AWS account using the external_id. [web:1][web:90]

data "aws_iam_policy_document" "splunk_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [signalfx_aws_external_integration.this.signalfx_aws_account]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [signalfx_aws_external_integration.this.external_id]
    }
  }
}

resource "aws_iam_role" "splunk_o11y" {
  name               = "${var.account_name}-splunk-o11y"
  assume_role_policy = data.aws_iam_policy_document.splunk_assume_role.json
}

resource "aws_iam_policy" "splunk_o11y" {
  name        = "${var.account_name}-splunk-o11y-policy"
  description = "Permissions required by Splunk Observability Cloud"

  policy = <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:DescribeAlarmsForMetric",
        "cloudwatch:ListMetricStreams",
        "cloudwatch:GetMetricStream",
        "cloudwatch:PutMetricStream",
        "cloudwatch:DeleteMetricStream",
        "cloudwatch:StartMetricStreams",
        "cloudwatch:StopMetricStreams",

        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",

        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeTags",
        "ec2:DescribeReservedInstances",
        "ec2:DescribeReservedInstancesModifications",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumeStatus",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",

        "tag:GetResources",
        "organizations:DescribeOrganization"
      ],
      "Resource": "*"
    }
  ]
}
JSON
}

resource "aws_iam_role_policy_attachment" "splunk_o11y_attach" {
  role       = aws_iam_role.splunk_o11y.name
  policy_arn = aws_iam_policy.splunk_o11y.arn
}

# --------- Splunk AWS integration ---------
# Uses integration_id, external_id, and roleArn. [web:2][web:89]

resource "signalfx_aws_integration" "this" {
  enabled                  = true
  integration_id           = signalfx_aws_external_integration.this.id
  external_id              = signalfx_aws_external_integration.this.external_id
  role_arn                 = aws_iam_role.splunk_o11y.arn

  regions                  = [var.aws_region]
  import_cloud_watch       = true
  use_metric_streams_sync  = true
  enable_aws_usage         = true
}

# --------- Splunk O11y dashboards (provider-compatible) ---------
# One dashboard group + 3 charts, then a dashboard that includes them. [web:139][web:136]

resource "signalfx_dashboard_group" "aws_account" {
  name = "${var.account_name} - AWS"
}

# Chart 1: ELB/ALB Request Count
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

# Chart 2: ELB/ALB 5xx Error Rate
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

# Chart 3: RDS CPU Utilization
resource "signalfx_time_chart" "rds_cpu" {
  name        = "${var.account_name} - RDS CPU Utilization"
  description = "Average CPU for RDS instances in ${var.aws_region}."
  plot_type   = "LineChart"

  program_text = <<-EOT
    data("aws.rds.cpuutilization",
         filter=filter("aws_region", "${var.aws_region}"),
         rollup="avg").publish()
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


# --------- Outputs ---------

output "external_id" {
  value     = signalfx_aws_external_integration.this.external_id
  sensitive = true
}

output "splunk_aws_account_id" {
  value     = signalfx_aws_external_integration.this.signalfx_aws_account
  sensitive = true
}

output "splunk_role_arn" {
  value = aws_iam_role.splunk_o11y.arn
}


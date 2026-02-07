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

# --------- Splunk external integration ---------

resource "signalfx_aws_external_integration" "this" {
  name = var.account_name
}

# --------- IAM role in your AWS account ---------

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
        
        
          "lambda:GetAlias",
          "lambda:ListFunctions",
          "lambda:ListTags"
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

# Outputs used by module B (optional, but handy)
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
output "external_integration_id" {
  value = signalfx_aws_external_integration.this.id
}

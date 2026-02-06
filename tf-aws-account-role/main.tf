terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

variable "region" {
  type = string
}

variable "aws_profile" {
  type = string
}

variable "external_id" {
  type = string
}

variable "splunk_aws_account_id" {
  type = string
}

variable "account_name" {
  type = string
}

data "aws_iam_policy_document" "splunk_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.splunk_aws_account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
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
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
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

output "splunk_role_arn" {
  value = aws_iam_role.splunk_o11y.arn
}

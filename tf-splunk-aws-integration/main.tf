terraform {
  required_providers {
    signalfx = {
      source  = "splunk-terraform/signalfx"
      version = "~> 6.14"
    }
  }
}

provider "signalfx" {
  auth_token = var.splunk_o11y_token
  api_url    = var.splunk_o11y_api_url
}

variable "account_name" {
  type = string
}

variable "regions" {
  type = list(string)
}

variable "splunk_o11y_token" {
  type      = string
  sensitive = true
}

variable "splunk_o11y_api_url" {
  type = string
}

resource "signalfx_aws_external_integration" "this" {
  name = var.account_name
}

resource "signalfx_aws_integration" "this" {
  enabled                 = true
  integration_id          = signalfx_aws_external_integration.this.id
  external_id             = signalfx_aws_external_integration.this.external_id
  regions                 = var.regions
  import_cloud_watch      = true
  use_metric_streams_sync = true
  enable_aws_usage        = true
}

output "external_id" {
  value = signalfx_aws_external_integration.this.external_id
}

output "splunk_aws_account_id" {
  value = signalfx_aws_external_integration.this.signalfx_aws_account
}

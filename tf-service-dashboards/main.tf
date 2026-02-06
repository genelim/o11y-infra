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

variable "splunk_o11y_token" {
  type      = string
  sensitive = true
}

variable "splunk_o11y_api_url" {
  type = string
}

variable "service_name" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_account_id" {
  type = string
}

resource "signalfx_dashboard" "service" {
  name        = "${var.service_name} - ${var.env}"
  description = "Standard service dashboard"

  charts {
    chart {
      name = "Request Count"
      program_text = <<-PROGRAM
        signal = data("http.server.request_count", filter=filter("service", "${var.service_name}") and filter("env", "${var.env}")).sum()
        signal
      PROGRAM
      chart_type = "TimeSeries"
    }
  }
}

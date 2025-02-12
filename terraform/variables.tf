variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for CloudFront"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "domain_name" {
  description = "Custom domain name for the CloudFront distribution"
  type        = string
}

variable "email_address" {
  type      = string
  sensitive = true
}

variable "pagerduty_integration_key" {
  description = "PagerDuty integration key"
  type        = string
  sensitive   = true
}

variable "pagerduty_integration_url" {
  description = "PagerDuty integration URL"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack_Webhook_URL"
  type        = string
  sensitive   = true
}


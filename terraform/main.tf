# Specify the AWS provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.8.0"
    }
  }
  required_version = ">= 1.10.3"
}

provider "aws" {
  region = "us-east-1" # Set the deployment region
}

data "aws_caller_identity" "current" {}


# S3 bucket for static website
resource "aws_s3_bucket" "cloud_resume_bucket" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name        = "Cloud Resume Bucket"
    Environment = "Production"
  }
}

# Enable versioning on S3 bucket
resource "aws_s3_bucket_versioning" "cloud_resume_versioning" {
  bucket = aws_s3_bucket.cloud_resume_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}


# S3 bucket CORS configuration
resource "aws_s3_bucket_cors_configuration" "cloud_resume_bucket_cors" {
  bucket = aws_s3_bucket.cloud_resume_bucket.id

  cors_rule {
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["https://fidelis-resume.fozdigitalz.com"] # Replace with your domain
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# S3 bucket policy for CloudFront access
resource "aws_s3_bucket_policy" "cloud_resume_policy" {
  bucket = aws_s3_bucket.cloud_resume_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = "s3:GetObject",
        Resource = "${aws_s3_bucket.cloud_resume_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.cloud_resume_distribution.id}"
          }
        }
      }
    ]
  })
}


# Read and replace placeholder in the HTML file dynamically
data "template_file" "cloud_resume_html" {
  template = file("${path.module}/cloud-resume.html")

  vars = {
    api_gateway_url = "https://${aws_api_gateway_rest_api.cloud_resume_api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.cloud_resume_stage.stage_name}"
  }
}

# Upload the updated HTML file to S3 after API Gateway is created
resource "aws_s3_object" "cloud_resume_html" {
  bucket              = aws_s3_bucket.cloud_resume_bucket.id
  key                 = "cloud-resume.html"
  content             = data.template_file.cloud_resume_html.rendered
  content_type        = "text/html"
  content_disposition = "inline"

  depends_on = [aws_api_gateway_stage.cloud_resume_stage]

  tags = {
    Name        = "Cloud Resume HTML"
    Environment = "Production"
  }
}


# Cloudfront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "cloud_resume_oac" {
  name                              = "cloud-resume-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


# CloudFront distribution
resource "aws_cloudfront_distribution" "cloud_resume_distribution" {
  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn # Attach WAF to CloudFront

  origin {
    domain_name = aws_s3_bucket.cloud_resume_bucket.bucket_regional_domain_name
    origin_id   = "S3-cloud-resume-origin"

    origin_access_control_id = aws_cloudfront_origin_access_control.cloud_resume_oac.id
  }

  enabled             = true
  default_root_object = "cloud-resume.html"

  aliases = [var.domain_name] # Custom domain name

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-cloud-resume-origin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # Viewer certificate for HTTPS
  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  # Restrictions block to meet CloudFront requirements
  restrictions {
    geo_restriction {
      restriction_type = "none" #Allows requests from all geographic locations
    }
  }
}


# Route 53 DNS configuration
resource "aws_route53_record" "cloud_resume_record" {
  zone_id = data.aws_route53_zone.fozdigitalz_com.zone_id
  name    = "fidelis-resume.fozdigitalz.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cloud_resume_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.cloud_resume_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route 53 hosted zone
data "aws_route53_zone" "fozdigitalz_com" {
  name = "fozdigitalz.com"
}

# DynamoDB table for visitor count
resource "aws_dynamodb_table" "visitor_count" {
  name         = "visitor-count"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
}


# Lambda function for visitor count
resource "aws_lambda_function" "visitor_counter" {
  filename         = "visitor_counter_lambda.zip" # Prebuilt zip with your Python code
  function_name    = "VisitorCounter"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "visitor_counter_lambda.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("visitor_counter_lambda.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.visitor_count.name
    }
  }
}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}


# Custom IAM Policy for Lambda to interact with DynamoDB & write to Cloudwatch logs
resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_dynamodb_cloudwatch_policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        Resource = "arn:aws:dynamodb:*:*:table/${aws_dynamodb_table.visitor_count.name}"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach policy to lambda
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# REST API Resource
resource "aws_api_gateway_rest_api" "cloud_resume_api" {
  name        = "CloudResumeAPI"
  description = "API for visitor counter"
}

# Root Resource ("/")
resource "aws_api_gateway_resource" "visitors" {
  rest_api_id = aws_api_gateway_rest_api.cloud_resume_api.id
  parent_id   = aws_api_gateway_rest_api.cloud_resume_api.root_resource_id
  path_part   = "visitors"
}

# API Gateway Method
resource "aws_api_gateway_method" "get_visitors" {
  rest_api_id   = aws_api_gateway_rest_api.cloud_resume_api.id
  resource_id   = aws_api_gateway_resource.visitors.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.cloud_resume_api.id
  resource_id             = aws_api_gateway_resource.visitors.id
  http_method             = aws_api_gateway_method.get_visitors.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.visitor_counter.invoke_arn
}

# Enable CORS for API Gateway- API Method Response
resource "aws_api_gateway_method_response" "cors_response" {
  rest_api_id = aws_api_gateway_rest_api.cloud_resume_api.id
  resource_id = aws_api_gateway_resource.visitors.id
  http_method = aws_api_gateway_method.get_visitors.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

#API Gateway Integration Response
resource "aws_api_gateway_integration_response" "cors_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.cloud_resume_api.id
  resource_id = aws_api_gateway_resource.visitors.id
  http_method = aws_api_gateway_method.get_visitors.http_method
  status_code = aws_api_gateway_method_response.cors_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'https://fidelis-resume.fozdigitalz.com'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.lambda_integration]
}

# API Gateway Deployment Stage with Throttling
resource "aws_api_gateway_deployment" "cloud_resume_deployment" {
  rest_api_id = aws_api_gateway_rest_api.cloud_resume_api.id

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method.get_visitors,
    aws_api_gateway_method_response.cors_response
  ]
}

#API Gateway Stage 
resource "aws_api_gateway_stage" "cloud_resume_stage" {
  deployment_id = aws_api_gateway_deployment.cloud_resume_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.cloud_resume_api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn  
    format = jsonencode({
      requestId       = "$context.requestId"
      ip              = "$context.identity.sourceIp"
      requestTime     = "$context.requestTime"
      httpMethod      = "$context.httpMethod"
      resourcePath    = "$context.resourcePath"
      status          = "$context.status"
      responseLength  = "$context.responseLength"
    })
  }

  tags = {
    Environment = "Production"
  }

  depends_on = [
    aws_api_gateway_account.api_logging,
    aws_cloudwatch_log_group.api_gateway_log_group
    ] 
}

#Enabled Logging & detailed Metrics for API Gateway Stage
resource "aws_api_gateway_method_settings" "cloud_resume_metrics" {
  rest_api_id = aws_api_gateway_rest_api.cloud_resume_api.id
  stage_name  = aws_api_gateway_stage.cloud_resume_stage.stage_name

  method_path = "visitors/GET"
  settings {
    metrics_enabled    = true
    data_trace_enabled = true
    logging_level      = "ERROR"
  }
}


# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.cloud_resume_api.execution_arn}/*/*"
}


# CloudWatch Log Group for API Gateway (optional)
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/apigateway/CloudResumeAPI"
  retention_in_days = 14
  
  #Terraform avoid deletion if API Gateway recreates the Log_Group
  lifecycle {
    ignore_changes = [name]
  }
}

#Grant API Gateway Permissions to Write to CloudWatch Logs
resource "aws_iam_role" "api_gw_cloudwatch_role" {
  name = "APIGatewayCloudWatchLogsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy_attachment" "api_gw_logging_policy" {
  name       = "ApiGatewayLoggingPolicy"
  roles      = [aws_iam_role.api_gw_cloudwatch_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

#Attach the IAM Role to API Gateway
resource "aws_api_gateway_account" "api_logging" {
  cloudwatch_role_arn = aws_iam_role.api_gw_cloudwatch_role.arn
}

# SNS topic resource for notifications
resource "aws_sns_topic" "api_alerts" {
  name = "CloudResumeAlerts"
}


#Allow HTTPS subscription  to SNS- PagerDuty
resource "aws_sns_topic_policy" "api_alerts_policy" {
  arn = aws_sns_topic.api_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = ["SNS:Subscribe", "SNS:Publish"],
        Resource  = aws_sns_topic.api_alerts.arn
        Condition = {
          StringEquals = {
            "sns:Protocol" = "https"
          }
        }
      }
    ]
  })
}

#Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.api_alerts.arn
  protocol  = "email"
  endpoint  = var.email_address
}


#Test PagerDuty Subscription Directly to SNS
resource "aws_sns_topic_subscription" "pagerduty_sub" {
  topic_arn = aws_sns_topic.api_alerts.arn
  protocol  = "https"
  endpoint  = "https://events.eu.pagerduty.com/integration/57fa85da4b2a4705c123220848ab63d8/enqueue"
  raw_message_delivery = true
}


#Store PagerDuty Integration URL in Secret Manager
resource "aws_secretsmanager_secret" "pagerduty_integration_url" {
  name = "pagerduty_integration_url"
}

resource "aws_secretsmanager_secret_version" "pagerduty_integration_url_value" {
  secret_id     = aws_secretsmanager_secret.pagerduty_integration_url.id
  secret_string = var.pagerduty_integration_url
}


#IAM Role for PagerDuty Lambda
resource "aws_iam_role" "sns_to_pagerduty_lambda_role" {
  name = "lambda_to_pagerduty_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy attachement for PagerDuty Lambda
resource "aws_iam_role_policy_attachment" "sns_lambda_secrets_access" {
  policy_arn = aws_iam_policy.lambda_sns_pagerduty_access.arn
  role       = aws_iam_role.sns_to_pagerduty_lambda_role.name
}

#IAM Policy for PagerDuty Lambda to Access Secret Manager & Make Requests to PagerDuty API
resource "aws_iam_policy" "lambda_sns_pagerduty_access" {
  name        = "lambda_sns_pagerduty_access"
  description = "Allow Lambda to access SNS, send events to PagerDuty, and write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "sns:Subscribe",
          "sns:Publish",
          "sns:ListSubscriptions",
          "sns:ListSubscriptionsByTopic"
        ]
        Resource = aws_sns_topic.api_alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.pagerduty_integration_url.arn
      },
      {
        Effect   = "Allow"
        Action   = "execute-api:Invoke"  # Permission for making API calls to PagerDuty
        Resource = "arn:aws:apigateway:*::/*"  # Allow Lambda to call any API
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"  # Allow Lambda to write logs to any CloudWatch Log group/stream
      }
    ]
  })
}



# Lambda function for PagerDuty integration
resource "aws_lambda_function" "lambda_to_pagerduty" {
  filename         = "lambda_to_pagerduty.zip"  # Prebuilt zip in my terraform directory
  function_name    = "lambda_to_pagerduty"      # Lambda name
  role             = aws_iam_role.sns_to_pagerduty_lambda_role.arn
  handler          = "lambda_to_pagerduty.lambda_handler"  
  runtime          = "python3.12"  # Or your preferred runtime
  source_code_hash = filebase64sha256("lambda_to_pagerduty.zip")  # Ensures Terraform tracks the zip file changes

  environment {
    variables = {
      PAGERDUTY_SECRET_ARN = aws_secretsmanager_secret.pagerduty_integration_url.arn
    }
  }
}

#PagerDuty Lambda subscription to SNS
resource "aws_sns_topic_subscription" "pagerduty_subscription" {
  topic_arn = aws_sns_topic.api_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.lambda_to_pagerduty.arn
  depends_on = [aws_lambda_function.lambda_to_pagerduty]
}

#Ensure SNS can Invoke PageDuty_lambda
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_to_pagerduty.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.api_alerts.arn
}



#Cloud Watch Alarm for API Gateway
resource "aws_cloudwatch_metric_alarm" "api_errors_alarm" {
  alarm_name          = "API-Error-Alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"

  dimensions = {
    ApiId = aws_api_gateway_rest_api.cloud_resume_api.id
  }

  alarm_description = "Triggers when there are 5XX errors in API Gateway"
  actions_enabled   = true
  alarm_actions     = [aws_sns_topic.api_alerts.arn]

  depends_on = [aws_api_gateway_rest_api.cloud_resume_api]
}

#CloudWatch alarm for visitor_counter_lambda
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "LambdaErrorAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Triggers when the Lambda function has errors."
  depends_on          = [aws_lambda_function.visitor_counter]
  alarm_actions       = [aws_sns_topic.api_alerts.arn]
  dimensions = {
    FunctionName = aws_lambda_function.visitor_counter.function_name
  }
}


# Create IAM Role for Slack Lambda
resource "aws_iam_role" "sns_to_slack_lambda_role" {
  name = "sns_to_slack_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

#Policy to allow Lambda Read from Secret Manager
resource "aws_iam_role_policy" "sns_to_slack_lambda_role_policy" {
  name = "sns-to-slack-lambda-policy"
  role = aws_iam_role.sns_to_slack_lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "secretsmanager:GetSecretValue",
        Resource = aws_secretsmanager_secret.slack_webhook_url.arn
      }
    ]
  })
}


# Attach Policies to Allow Slack Lambda to Read from SNS and Write Logs to slack
resource "aws_iam_role_policy" "sns_to_slack_policy" {
  name = "sns_to_slack_policy"
  role = aws_iam_role.sns_to_slack_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "logs:CreateLogGroup",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow",
        Action   = ["sns:Subscribe", "sns:Receive"],
        Resource = "${aws_sns_topic.api_alerts.arn}"
      },
      {
        Effect   = "Allow",
        Action   = "lambda:InvokeFunction",
        Resource = "${aws_lambda_function.sns_to_slack.arn}"
      },

      {
        # this policy allows Lambda to publish messages to SNS
        Effect   = "Allow",
        Action   = "sns:Publish",
        Resource = "${aws_sns_topic.api_alerts.arn}"
      }

    ]
  })
}


# Create Lambda_to_Slack Function & retrieve slack webhookurl from AWS Secret Manager
resource "aws_lambda_function" "sns_to_slack" {
  filename      = "lambda_to_slack.zip"  # Zip your Python script before deployment
  function_name = "SNS-to-Slack"
  role          = aws_iam_role.sns_to_slack_lambda_role.arn
  handler       = "lambda_to_slack.lambda_handler"
  runtime       = "python3.9"
  timeout       = 10

  environment {
    variables = {
      SLACK_WEBHOOK_SECRET_NAME = aws_secretsmanager_secret.slack_webhook_url.name  # Reference to the secret
    }
  }

  # Lambda function's permission to access the secret (already done via IAM role policy)
  depends_on = [
    aws_secretsmanager_secret.slack_webhook_url
  ]
}

#Store the Webhook URL in AWS Secrets Manager
resource "aws_secretsmanager_secret" "slack_webhook_url" {
  name        = "slack-webhook-url"
  description = "Slack Webhook URL for Lambda"
}

resource "aws_secretsmanager_secret_version" "slack_webhook_url_version" {
  secret_id     = aws_secretsmanager_secret.slack_webhook_url.id
  secret_string = jsonencode({
    slack_webhook_url = var.slack_webhook_url
  })
}

# Grant SNS permission to invoke Lambda
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_to_slack.function_name
  principal     = "sns.amazonaws.com"
  source_arn = aws_sns_topic.api_alerts.arn
  depends_on    = [aws_lambda_function.sns_to_slack]
}


# Subscribe Slack Lambda to SNS Topic
resource "aws_sns_topic_subscription" "sns_to_slack_subscription" {
  topic_arn = aws_sns_topic.api_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_to_slack.arn
  depends_on = [aws_lambda_permission.allow_sns] #Waits for Lambda perssion before subscription
}

#AWS WAF resource to front Cloudfront
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  name        = "cloudfront-waf"
  description = "WAF for CloudFront"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000 # Adjust based on your expected traffic
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CloudFrontWAF"
    sampled_requests_enabled   = true
  }
}

#Terraform Backend (S3 for State MAnagement)
terraform {
  backend "s3" {
    bucket  = "foz-terraform-state-bucket"
    key     = "infrastructure.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
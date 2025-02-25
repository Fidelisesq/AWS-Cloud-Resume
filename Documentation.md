![Result-Page](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Result-page1.png)
![Result-Page-2](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Result-Page2.png)

# **Hosting a Serverless Resume Website on AWS with Terraform and CI/CD**

Building a serverless resume website on AWS isn’t just about hosting a static page. It is like assembling a high-performance engine. When I decided to create my resume website, I wanted it to be more than just a digital placeholder—it had to be scalable, secure, and cost-efficient. Each component—S3, CloudFront, Lambda, DynamoDB, API Gateway, Route53+DNSSEC to Monitoring tools and AWS WAF—plays a critical role, while Terraform and GitHub CI/CD act as the control systems, ensuring everything runs smoothly. The result? A scalable, secure, and cost-efficient website. Let’s take a closer look under the hood!

---

## **Project Overview**
The goal of this project was to enhance the accessibility and visibility of my resume by hosting it as a responsive website. The website is built using serverless technologies, ensuring minimal operational overhead and maximum scalability. Here’s a high-level breakdown of the architecture:

1. **Frontend**: A static HTML resume hosted on **Amazon S3** and served via **CloudFront** for global content delivery.
2. **Backend**: A serverless REST API built with **AWS Lambda** and **API Gateway** to handle dynamic functionality (e.g., visitor counter).
3. **Database**: **DynamoDB** to store and retrieve data (e.g., visitor counts).
4. **Security**: **AWS WAF** to protect the website from common web exploits.
5. **DNS and DNSSEC**: **Route 53** for DNS management and DNSSEC for enhanced security.
6. **Monitoring and Alerts**: **CloudWatch**, **SNS**, **PagerDuty**, and **Slack** for monitoring and notifications.
7. **Infrastructure as Code**: **Terraform** to define and provision all AWS resources.
8. **CI/CD**: Automated deployment pipeline using **GitHub Actions**.

---

## **Terraform Configuration**

The entire infrastructure is defined using Terraform, ensuring reproducibility and scalability. Below is a detailed explanation of the Terraform configuration. `Note:` You can find all configuration files in my [Github.](https://github.com/Fidelisesq/AWS-Cloud-Resume)

---

### **1. Frontend: S3 and CloudFront**

The frontend consists of a static HTML file hosted on an S3 bucket and served via CloudFront. The bucket is configured with versioning, CORS, and a policy to allow access only via CloudFront.

```hcl
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
```

- **S3 Bucket**: Stores the static HTML file for the resume.
- **Versioning**: Enabled to keep track of changes.
- **CORS**: Allows cross-origin requests from the custom domain, which I specied in the S3 CORS policy.
- **Bucket Policy**: Restricts access to the bucket, allowing only CloudFront to serve the content.

#### **Challenges & Strategies**
CORS setting was my major challenge here as browswers were blocking requests to S3 bucket due to incorrect CORS headers. I checked AWS documentation & used browser developers tools to debug and setup cache invalidation as Cloudfront was still serving old contents even though my CORS is now updated. For HTTPS & custom domain, I followed AWS best practices to set up ACM and Route 53, ensuring a secure and reliable custom domain setup.

---

### **2. Backend: Lambda, DynamoDB, and API Gateway**

The backend consists of a Lambda function to handle visitor counts, a DynamoDB table to store the counts, and an API Gateway to expose the Lambda function as a REST API.

#### **Lambda Function for Visitor Count**

```hcl
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
```

#### **DynamoDB Table**

```hcl
# DynamoDB table for visitor count
resource "aws_dynamodb_table" "visitor_count" {
  name           = "VisitorCount"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
```

#### **API-Gateway Integration**

```hcl
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

```
- **Lambda Function**: Handles the logic for retrieving & incrementing and visitor counts.
- **Environment Variables**: Passes the DynamoDB table name to the Lambda function.
- **DynamoDB Table**: Stores the visitor count with a primary key `id`.
- **API Gateway**: Exposes the Lambda function as a REST API.
- **Integration**: Connects the API Gateway to the Lambda function.

#### **Challenges & Strategies**
I spent time here writing the Lambda Function code that checks DynamoDB table, retreive the count and updates it. My function needed a paramenter to recognise a unique visitor I tried `Browser LocalStorage` but it increment count on reload by thesame user. I also tried `Session` and `Cookie` until I settled for IP address. My function stores the hash of unique IP in my DynamoDB table to check unique visitors. `The hash is a One-Way process, so I can't recover the IPs from it.` I ran Postman to test my API-Gateway and fixed permission issues not allowing API-Gatway to invoke my Lambda.

---

### **3. Monitoring and Alerts**

The project includes monitoring and alerting using CloudWatch, SNS, PagerDuty, and Slack.

#### **CloudWatch Alarms**

```hcl
# CloudWatch Alarm for API Gateway
resource "aws_cloudwatch_metric_alarm" "api_errors_alarm" {
  alarm_name          = "API-Error-Alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "IntegrationLatency"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"

  dimensions = {
    ApiId = aws_api_gateway_rest_api.cloud_resume_api.id
  }

  alarm_description = "Triggers when API Gateway returns a 502 error"
  actions_enabled   = true
  alarm_actions     = [aws_sns_topic.api_alerts.arn]
}
```

#### **SNS Topic for Notifications**

```hcl
# SNS topic resource for notifications
resource "aws_sns_topic" "api_alerts" {
  name = "CloudResumeAlerts"
}
```

####  **SNS Policy to Allow Subscriptions & Limit Publish to Only CloudWatch**
```hcl
# Allow HTTPS, email, & Lambda subscriptions to SNS & restrict publish to SNS to only CloudWatch
resource "aws_sns_topic_policy" "api_alerts_policy" {
  arn = aws_sns_topic.api_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudWatchPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.api_alerts.arn
      },
      {
        Sid       = "AllowEmailSubscription"
        Effect    = "Allow"
        Principal = "*"
        Action    = "SNS:Subscribe"
        Resource  = aws_sns_topic.api_alerts.arn
        Condition = { StringEqualsIfExists = { "sns:Protocol" = "email" } }
      },
      {
        Sid       = "AllowHttpsSubscription"
        Effect    = "Allow"
        Principal = "*"
        Action    = "SNS:Subscribe"
        Resource  = aws_sns_topic.api_alerts.arn
        Condition = { StringEqualsIfExists = { "sns:Protocol" = "https" } }
      },
      {
        Sid       = "AllowLambdaSubscription"
        Effect    = "Allow"
        Principal = "*"
        Action    = "SNS:Subscribe"
        Resource  = aws_sns_topic.api_alerts.arn
        Condition = { StringEqualsIfExists = { "sns:Protocol" = "lambda" } }
      }
    ]
  })
}
```

#### **Email Subscription**

```hcl
#Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.api_alerts.arn
  protocol  = "email"
  endpoint  = var.email_address
}
```

#### **PagerDuty Integration**

```hcl

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

#Create Lambda Layer to hold dependencies that can forward request to PagerDuty
resource "aws_lambda_layer_version" "pagerduty_lambda_layer" {
  layer_name  = "pagerduty_lambda_layer"
  filename    = "lambda_layer.zip"  # Path to your Lambda layer zip file
  source_code_hash = filebase64sha256("lambda_layer.zip")  # Ensure Terraform tracks changes

  compatible_runtimes = ["python3.12"]  # Use the runtime compatible with your Lambda function
}

# Lambda function for PagerDuty integration + layers
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

  layers = [
    aws_lambda_layer_version.pagerduty_lambda_layer.arn  # Attach the Lambda layer here
  ]
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

```

#### **Slack Integration**

```hcl
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

# Create Lambda_to_Slack Function & retrieve slack webhook URL from AWS Secret Manager
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

```
- **CloudWatch Alarms**: Monitors API Gateway and Lambda for errors and latency.
- **SNS Topic**: Centralised notification system for alerts. My slack & Email & PagerDuty were subscribed to my SNS.
- **PagerDuty Integration**: Sends alerts to PagerDuty for critical issues.
- **Slack Integration**: Sends notifications to a Slack channel for non-critical alerts.

#### **Challenges & Strategies**
While SNS allowed HTTPS subscription for PagerDuty integration, it can't retrieve my integration URL from AWS Secret Manager and it can't natively forward messages to Slack App. So, I employed two Lamba functions, which subsribed to SNS and forwared alerts generated by CloudWatch to my Slack App & PagerDuty for phone notifications.

---

### **4. Security: AWS WAF & DNNSEC**

The website is protected by AWS WAF to prevent common web exploits while activating DNSSEC for my domain enhances security by preventing attackers from tampering with DNS responses and ensuring the integrity and authenticity of the domain's DNS data.

#### **WAF Integration with Cloudfront**
```hcl
# AWS WAF resource to front CloudFront
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
}
```
#### **Route53 Custom Domain & DNSSEC**

```hcl
# Fetch the Route 53 hosted zone info for fozdigitalz.com
data "aws_route53_zone" "fozdigitalz_com" {
  name = "fozdigitalz.com"
}

# Route 53 DNS configuration
resource "aws_route53_record" "cloud_resume_record" {
  zone_id = data.aws_route53_zone.fozdigitalz_com.zone_id
  name    = "fidelis-resume.fozdigitalz.com"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.cloud_resume_distribution.domain_name]
}

# Create the KMS key (without setting the policy initially)
resource "aws_kms_key" "dnssec_key" {
  description             = "KMS key for Route 53 DNSSEC signing"
  deletion_window_in_days = 30
  key_usage               = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
}

# Define the KMS key policy
resource "aws_kms_key_policy" "dnssec_key_policy" {
  key_id = aws_kms_key.dnssec_key.key_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "dnssec-route53.amazonaws.com" }
        Action   = [ "kms:Encrypt", "kms:Decrypt", "kms:GetPublicKey", "kms:Sign", "kms:DescribeKey" ]
        Resource = aws_kms_key.dnssec_key.arn
      },
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = [ "kms:*"]
        Resource = aws_kms_key.dnssec_key.arn
      },
      # Allow my IAM User to get and put key policies
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/Fidelisesq" }
        Action   = [
          "kms:*"
        ]
        Resource = aws_kms_key.dnssec_key.arn
      }
    ]
  })
}

# Create the DNSSEC key signing key
resource "aws_route53_key_signing_key" "dnssec_kms_key" {
  hosted_zone_id = data.aws_route53_zone.fozdigitalz_com.zone_id
  name           = "dnssec-kms-key"
  key_management_service_arn = aws_kms_key.dnssec_key.arn
}

# Enable DNSSEC for the hosted zone
resource "aws_route53_hosted_zone_dnssec" "dnssec" {
  hosted_zone_id = data.aws_route53_zone.fozdigitalz_com.zone_id
  depends_on = [ aws_route53_key_signing_key.dnssec_kms_key ]
}
```

- **AWS WAF**: Protects the website from DDoS attacks and other web exploits.

#### **Challenges & Strategies**
Not really a challenge here but I got to discover that AWS WAF won't wotk with the HTTP API. So, I opted for the REST API with WAF to protect it. Later on, I placed WAF before my Cloudfront and introduced throttling to my REST API.

---

### **5. CI/CD Pipeline**

The infrastructure is deployed using a CI/CD pipeline powered by GitHub Actions. The Terraform state is stored in an S3 bucket for state management.

#### **GitHub Actions Workflow**

The workflow is triggered on a push to the `main` branch or manually via the `workflow_dispatch` event. It supports two actions: **create** (deploy infrastructure) and **destroy** (tear down infrastructure).

```yaml
name: Deploy Infrastructure

on:
  push:
    branches:
      - main
  workflow_dispatch:
    inputs:
      action:
        description: "Action to perform (create or destroy)"
        required: true
        type: choice
        options:
          - create
          - destroy

jobs:
  infrastructure-deployment:
    if: >-
      (github.event_name == 'push' && !contains(github.event.head_commit.message, 'destroy')) ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'create')
    name: "Infrastructure Deployment"
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Set AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_DEFAULT_REGION }}

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.10.3

      - name: Create terraform.tfvars
        run: |
          cat <<EOF > terraform/terraform.tfvars
          acm_certificate_arn = "${{ secrets.ACM_CERTIFICATE_ARN }}"
          aws_access_key_id = "${{ secrets.AWS_ACCESS_KEY_ID }}"
          aws_secret_access_key = "${{ secrets.AWS_SECRET_ACCESS_KEY }}"
          aws_region = "${{ secrets.AWS_REGION }}"
          bucket_name = "${{ secrets.BUCKET_NAME }}"
          domain_name = "${{ secrets.DOMAIN_NAME }}"
          email_address = "${{ secrets.EMAIL_ADDRESS }}"
          pagerduty_integration_url = "${{ secrets.PAGERDUTY_INTEGRATION_URL }}"
          pagerduty_integration_key = "${{ secrets.PAGERDUTY_INTEGRATION_KEY }}"
          slack_webhook_url = "${{ secrets.SLACK_WEBHOOK_URL }}"
          EOF

      - name: Mask AWS Account ID in Logs
        run: echo "::add-mask::${{ secrets.AWS_ACCOUNT_ID }}"

      - name: Terraform Init
        id: init
        run: cd terraform && terraform init

      - name: Terraform Validate
        id: validate
        run: cd terraform && terraform validate

      - name: Terraform Plan
        id: plan
        run: cd terraform && terraform plan -out=tfplan

      - name: Terraform Apply
        id: apply
        run: cd terraform && terraform apply -auto-approve tfplan

  infrastructure-cleanup:
    if: >-
      (github.event_name == 'push' && contains(github.event.head_commit.message, 'destroy')) ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'destroy')
    name: "Infrastructure Cleanup"
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Set AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_DEFAULT_REGION }}

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.10.3

      - name: Create terraform.tfvars
        run: |
          cat <<EOF > terraform/terraform.tfvars
          acm_certificate_arn = "${{ secrets.ACM_CERTIFICATE_ARN }}"
          aws_access_key_id = "${{ secrets.AWS_ACCESS_KEY_ID }}"
          aws_secret_access_key = "${{ secrets.AWS_SECRET_ACCESS_KEY }}"
          aws_region = "${{ secrets.AWS_DEFAULT_REGION }}"
          bucket_name = "${{ secrets.BUCKET_NAME }}"
          domain_name = "${{ secrets.DOMAIN_NAME }}"
          email_address = "${{ secrets.EMAIL_ADDRESS }}"
          pagerduty_integration_url = "${{ secrets.PAGERDUTY_INTEGRATION_URL }}"
          pagerduty_integration_key = "${{ secrets.PAGERDUTY_INTEGRATION_KEY }}"
          slack_webhook_url = "${{ secrets.SLACK_WEBHOOK_URL }}"
          EOF

      - name: Mask AWS Account ID in Logs
        run: echo "::add-mask::${{ secrets.AWS_ACCOUNT_ID }}"

      - name: Terraform Init
        id: init
        run: cd terraform && terraform init

      - name: Terraform Destroy
        id: destroy
        run: cd terraform && terraform destroy -auto-approve
```

- **Workflow Triggers**: The workflow is triggered on a push to the `main` branch or manually via the `workflow_dispatch` event.
- **Terraform Steps**: The workflow initializes, validates, plans, and applies the Terraform configuration for deployment. For cleanup, it destroys the infrastructure.
- **Secrets Management**: Sensitive values like AWS credentials, ACM certificate ARN, and Slack webhook URL are stored in GitHub Secrets.

#### **Challenges & Strategies**

`Screenshot of suuccessful End-to-End Design Test`
![Cypress end-to-end-test](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-33.png)

![Cypress end-to-end-test-2](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-2.png)

![Cypress end-to-end-test-3](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-11.png)

<p float="left">
  <img src="https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-2.png" width="200" />
  <img src="https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-11.png" width="200" /> 
</p>

---

### **6. Automated Testing with Cypress**

To ensure the website functions as expected after deployment, I implemented automated end-to-end (E2E) tests using **Cypress**. These tests are triggered automatically after a successful infrastructure deployment, ensuring that the website is not only deployed but also fully functional.

#### **Cypress Workflow**

The Cypress tests are executed in a separate GitHub Actions workflow that runs after the `Deploy Infrastructure` workflow completes successfully. Here’s how it works:

1. **Pre-Check Step**:
   - The workflow first verifies that the `infrastructure-deployment` job in the `Deploy Infrastructure` workflow has succeeded.
   - If the deployment is confirmed as successful, the Cypress tests are initiated.

2. **Cypress Execution**:
   - The workflow sets up Node.js, installs the necessary dependencies, and proceeds to run the Cypress tests.
   - Before executing the tests, the workflow waits for the website to become available at `https://fidelis-resume.fozdigitalz.com/`.
   - Test results are recorded and can be accessed in the Cypress Dashboard for detailed analysis.

```yaml
name: Cypress Tests

on:
  workflow_run:
    workflows: ["Deploy Infrastructure"]
    types:
      - completed
    branches:
      - main  # Specify the branch(es) where the workflow should run

jobs:
  cypress-run:
    runs-on: ubuntu-latest
    if: github.event.workflow_run.conclusion == 'success'  # Ensure the workflow only runs if the deployment succeeded
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '16'

      - name: Install dependencies
        run: npm install

      - name: Cypress run
        uses: cypress-io/github-action@v6
        with:
          wait-on: 'https://fidelis-resume.fozdigitalz.com/'
          wait-on-timeout: 60
          record: true
        env:
          CYPRESS_RECORD_KEY: ${{ secrets.CYPRESS_RECORD_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Save Cypress status
        id: cypress-status
        run: |
          if [ "${{ job.status }}" == "success" ]; then
            echo "Cypress tests passed!"
            echo "cypress-status=success" >> $GITHUB_OUTPUT
          else
            echo "Cypress tests failed!"
            echo "cypress-status=failure" >> $GITHUB_OUTPUT
          fi
```

- **Cypress Tests**: The test validates the website's functionality, including features like the visitor counter, which proves the backend resources are working and overall responsiveness.
- **Test Recording**: Results are recorded in the Cypress Dashboard for further review and analysis.

#### **Challenges & Strategies**
I wanted something else - make the Cypress Test run only when the the `Infrastrucure- Deployment` job in my main workflow runs successfully & skip when the `Infrastructure Cleanup` job runs. However, GitHub Actions does not directly support triggering a workflow from a specific job within another workflow. So, I must combine `workflow_run` event & job outputs to conditionaly achieve it. Guess what, I skipped this part so my test workflow runs whether I deploy or cleanup. I'd learn to make it better in my next improvement. 

---

## **Conclusion**

This project demonstrates how to build a scalable, secure, and cost-efficient serverless resume website on AWS. By leveraging Terraform for infrastructure as code and GitHub Actions for CI/CD, the entire deployment process is automated and reproducible. The use of serverless technologies ensures minimal operational overhead, while monitoring and alerting systems provide visibility into the system’s health..


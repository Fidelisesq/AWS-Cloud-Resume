![Architectural Diagram](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/AWS%20Cloud%20Resume.png)

# **Hosting a Serverless Resume Website on AWS with Terraform and CI/CD**

Building a serverless resume website on AWS isn’t just about hosting a static page. It is like assembling a high-performance engine. When I decided to create my resume website, I wanted it to be more than just a digital placeholder—it had to be scalable, secure, and cost-efficient. 

Each component—S3, CloudFront, Lambda, DynamoDB, API Gateway, Route53+DNSSEC to Monitoring tools and AWS WAF—plays a critical role, while Terraform and GitHub CI/CD act as the control systems, ensuring everything runs smoothly. Along the way, I encountered several `challenges` at different stages, from infrastructure setup to automation, and documented my `approach` to resolving them. The result? A scalable, secure, and cost-efficient website. Let’s take a closer look under the hood!

---

## **Project Overview**
The goal of this project was to enhance the accessibility and visibility of my resume by hosting it as a responsive website. The website is built using serverless technologies, ensuring minimal operational overhead and maximum scalability. Here’s a high-level breakdown of the architecture:

1. **Terraform Configuration**  
   I. **Provider, Identity Configuration + Terraform State Management**: Terraform version specified while **AWS S3** stores Terraform state. 
   II. **Frontend**: A static HTML resume hosted on **Amazon S3** and served via **CloudFront** for global content delivery. 
   III. **Backend**: A serverless REST API built with **AWS Lambda** and **API Gateway** to handle dynamic functionality & DynamoDB to store visitor count.  
   IV. **Monitoring and Alerts**: **CloudWatch**, **SNS**, **PagerDuty**, and **Slack** for monitoring and notifications.  
   V. **Security & DNS**: **AWS WAF, Route53 & DNSSEC** WAF to protect the website from common web exploits while Route53 for DNS management and DNSSEC for enhanced domain security. 
   VI. **Provider Block & Terraform State Management**: S3 is used for centralised storage ensurng a reliable state management. 

2. **Code Test+ CI/CD**: Automated deployment pipeline using **GitHub Actions**.  
3. **End-to-End Test**: Automated test of site functionality and app backend using Cypress.  
4. **Results**: The resume website is globally available, secure, and scalable. The visitor count updates dynamically via the backend, and CloudWatch monitors API health. CI/CD ensures quick updates with automated testing, improving reliability.  
5. **Conclusion**: Summary of the project and lessons learnt. 
---

## **1. Terraform Configuration**

The entire infrastructure is defined using Terraform (Infrastructure as Code), ensuring reproducibility and scalability. Below is a detailed explanation of the Terraform configuration. `Note:` You can find all configuration files in my [Github.](https://github.com/Fidelisesq/AWS-Cloud-Resume)


### **I. Provider Block & Terraform State Management**

The configuration uses **Amazon S3** for centralized state management, storing the `infrastructure.tfstate` file in the `foz-terraform-state-bucket` with encryption enabled. The **AWS provider** (version `>= 5.8.0`) is configured for deployment in the `us-east-1` region, and the Terraform version is set to `>= 1.10.3`. Additionally, the `aws_caller_identity` data resource retrieves information about the currently authenticated AWS account. This setup ensures secure, reliable state management and deployment configuration.

```hcl
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
# Declare the caller identity data resource
data "aws_caller_identity" "current" {}

#Terraform Backend (S3 for State Management)
terraform {
  backend "s3" {
    bucket  = "foz-terraform-state-bucket"
    key     = "infrastructure.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```
---

### **II. Frontend: S3 & CloudFront**

The frontend consists of a static HTML file hosted on an S3 bucket and served via CloudFront. The bucket is configured with versioning, CORS, and a policy to allow access only via CloudFront. Terraform uses `template_file` to replace  the API-Gateway invocation URL place holder in the script on my html document with the real URL once API-Gateway is created & deployed. Once that is done, terraform copies the html to the s3 bucket.

#### **S3, Policy & CORS**
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
```
#### **CloudFront Distribution**

```hcl
#Cloudfront Origin Access Control (OAC)
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
```

#### **Challenges & Strategies**
CORS setting was my major challenge here as browswers were blocking requests to S3 bucket due to incorrect CORS headers. I checked AWS documentation & used browser developers tools to debug and setup cache invalidation as Cloudfront was still serving old contents even though my CORS is now updated. For HTTPS & custom domain, I followed AWS best practices to set up ACM and Route 53, ensuring a secure and reliable custom domain setup.

---

### **III. Backend: Lambda, DynamoDB, and API Gateway**

The **Lambda function** handles the logic for retrieving and incrementing the visitor count, with **environment variables** passing the DynamoDB table name. The **DynamoDB table** stores the visitor count using a primary key `id`, while **API Gateway** exposes my Visitor_Counter Lambda function as a REST API, integrating it seamlessly for dynamic functionality.

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

#### **Challenges & Strategies**
I spent time here writing the Lambda Function code that checks DynamoDB table, retreive the count and updates it. My function needed a paramenter to recognise a unique visitor. I tried `Browser LocalStorage` but it increments count when I refresh the page on thesame browser. I also tried `Session` and `Cookie` until I settled for IP address. My function stores the hash of unique IPs in my DynamoDB table to check unique visitors. `The hash is a One-Way process, so I can't see the IPs and I can't recover them from the hashes.` I ran Postman to test my API-Gateway and fixed permission issues not allowing API-Gatway to invoke my Lambda.

---

### **IV. Monitoring and Alerts**

In this section of the project, I set up comprehensive monitoring and alerting using AWS CloudWatch, SNS, PagerDuty, and Slack to ensure timely responses to issues. I created a CloudWatch alarm to monitor API Gateway errors, triggering notifications through SNS when certain thresholds are met. I also configured an SNS topic to handle notifications and a policy to restrict publishing to CloudWatch only. For incident management, I integrated PagerDuty to alert on critical issues and used AWS Lambda to forward messages to PagerDuty. Additionally, I set up Slack integration to notify the team in real-time via a Lambda function that listens to the SNS topic, ensuring the team is always in the loop.

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

`Lambda Error Email Notification`
![Lambda-Error-Notification](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Email%20error-1.png)

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
  source_code_hash = filebase64sha256("lambda_layer.zip")  # Ensures Terraform tracks changes

  compatible_runtimes = ["python3.12"]  #
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
`PagerDuty Getting Alerts from Lambda`

![PagerDuty Alert-1](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/PagerDuty-2.png)

| ![PagerDuty Alert-2](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/PagerDuty-1.png) | ![PagerDuty Alert-3](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/PagerDuty-333.PNG) |
|---|---|

`PagerDuty App Push Notification`
| ![PagerDuty Alert-4](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/PagerDuty-4.jpg) | ![PagerDuty Alert-5](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/PagerDuty-5.jpg) |
|---|---|


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
`Slack Alert from SNS-Lambda`

![Slack-alert](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Slack%20Notification-1.png)


#### **Challenges & Strategies**
While SNS allowed HTTPS subscription for PagerDuty integration, it can't retrieve my integration URL from AWS Secret Manager and it can't natively forward messages to Slack App. So, I employed two Lamba functions, which subsribed to SNS and forwared alerts generated by CloudWatch to my Slack App & PagerDuty for phone notifications.

---

### **V. Security & DNS: AWS WAF, Route53 & DNSSEC**

The WAF configuration protects the website by blocking excessive traffic from a single IP (rate limiting), known bad IPs associated with reconnaissance and DDoS attacks, and malicious inputs. It also applies AWS-managed rule sets to prevent common vulnerabilities like cross-site scripting (XSS) and SQL injection, while providing visibility through CloudWatch metrics. Activating DNSSEC for my domain enhances security by preventing attackers from tampering with DNS responses and ensuring the integrity and authenticity of the domain's DNS data while Route53 provides the custom domain.

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

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # Amazon IP Reputation List (Blocks known bad IPs, reconnaissance, DDoS)
  rule {
    name     = "AmazonIPReputationRule"
    priority = 2

    override_action { 
      count {} 
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"

        # OPTIONAL: Override specific rules inside the group
        rule_action_override {
          action_to_use {
            block {}
          }
          name = "AWSManagedIPReputationList"
        }

        rule_action_override {
          action_to_use {
            block {}
          }
          name = "AWSManagedReconnaissanceList"
        }

        rule_action_override {
          action_to_use {
            count {}
          }
          name = "AWSManagedIPDDoSList"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AmazonIPReputationRule"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Known Bad Inputs Rule Set
  rule {
    name     = "KnownBadInputsRule"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsRule"
      sampled_requests_enabled   = true
    }
  }
  
  # AWS Managed Common Rule Set
rule {
  name     = "CommonRuleSet"
  priority = 4

  override_action {
    none {}  # Ensures AWS WAF applies its built-in block actions
  }

  statement {
    managed_rule_group_statement {
      vendor_name = "AWS"
      name        = "AWSManagedRulesCommonRuleSet"

      # Override specific rules that are set to "Count" by default, so they actually block bad traffic.
      rule_action_override {
        action_to_use {
          block {}
        }
        name = "CrossSiteScripting_URIPATH_RC_COUNT"
      }

      rule_action_override {
        action_to_use {
          block {}
        }
        name = "CrossSiteScripting_BODY_RC_COUNT"
      }

      rule_action_override {
        action_to_use {
          block {}
        }
        name = "CrossSiteScripting_QUERYARGUMENTS_RC_COUNT"
      }

      rule_action_override {
        action_to_use {
          block {}
        }
        name = "CrossSiteScripting_COOKIE_RC_COUNT"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CommonRuleSet"
    sampled_requests_enabled   = true
  }
}

  # Visibility config for the WAF ACL itself
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CloudFrontWAF"
    sampled_requests_enabled   = true
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
`DNSSEC Activated`
| ![DNNSEC Active-1](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/DNSSEC%20Active-1.png) | ![DNSSEC Active-2](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/DNSSEC%20Active-2.png) |
|---|---|

#### **Challenges & Strategies**
Not really a challenge here but I got to discover that AWS WAF won't work with the HTTP API. So, I opted for the REST API with WAF to protect it. Later on, I placed WAF before my Cloudfront and introduced throttling to my REST API. When WAF worked, using `AWSManagedRules` gave me issues. So, I checked the documentation for each rule and discovered the issue was me overriding some rules in my terraform config when the default actions was already set by AWS either as `count` or `block`. Secondly, I initially created a KMS key needed for my DNSSEC without an active policy that grants me necessary permission like `PutKeyPolicy` & `Disable + DeleteKey` so it locked me out when I needed to modify `Sign` & `Verify` permission for `Route53`. I had to contact `AWS` support for help because I can't modify it nor schedule for deletion. 

---

## **2. Code Test + CI/CD Pipeline**

In this workflow, I set up a GitHub Actions pipeline to deploy and manage infrastructure using Terraform. The pipeline includes steps for testing the Lambda function that counts visitors on the website and ensures the tests are successful before proceeding with the infrastructure deployment. I also added functionality for both creating and destroying resources based on user input or commit messages. For deployment, I configured Terraform to provision the necessary resources on AWS, including creating and applying a Terraform plan with secrets securely stored in GitHub. Additionally, I implemented a cleanup process that destroys infrastructure when required, ensuring efficient resource management.

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
  visitor-count-lambda-function-test:
    name: "Visitor Count Lambda Function Test"
    runs-on: ubuntu-latest
    if: >-
      !(github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'destroy') &&
      !(github.event_name == 'push' && contains(github.event.head_commit.message, 'destroy'))
    steps:
      - name: Checkout the code
        uses: actions/checkout@v4.2.2

      - name: Set up Python
        uses: actions/setup-python@v5.4.0
        with:
          python-version: '3.8'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements-test.txt

      - name: Set up AWS credentials
        uses: aws-actions/configure-aws-credentials@v4.1.0
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Run tests with pytest
        run: |
          pytest tests/visitor_counter_testscript.py

  infrastructure-deployment:
    if: >-
      (github.event_name == 'push' && !contains(github.event.head_commit.message, 'destroy') && needs.visitor-count-lambda-function-test.result == 'success') ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'create' && needs.visitor-count-lambda-function-test.result == 'success')
    name: "Infrastructure Deployment"
    runs-on: ubuntu-latest
    needs: visitor-count-lambda-function-test
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

`Screenshot of successful End-to-End Design Test`

![Cypress end-to-end-test](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-2.png)


| ![Image 1](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-33.png) | ![Image 2](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Cypress-Test-11.png) |
|---|---|

#### **Challenges & Strategies**
When I started I had partial success of deplpyment here and there. I actually lost count of the number of `Workflow Runs` before I got a clean successfull run. This section came with lots of debugging, learning to use `event`status and conditions to achieve my goal.

---

## **3. End-to-End Test with Cypress**

In this Cypress workflow, I run tests on the deployed resume website to ensure its functionality after the infrastructure is successfully deployed. The workflow triggers once the `Deploy Infrastructure` workflow completes, confirming the deployment was successful before starting the Cypress tests. 

The tests check various elements on the page, such as verifying that my name appears, confirming the presence of key sections like "Professional Summary" and "Personal Project Experience," and ensuring links to my GitHub, LinkedIn, and blog work correctly. Additionally, I check the visitor count and ensure that no images are broken on the page. The results are then recorded and accessible in the Cypress Dashboard for analysis.

#### **Cypress Workflow**

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

#### **Challenges & Strategies**

Using Cypress was easy to run the test. I got a good part of my the workflow from my Cypress Cloud dashboard after creating an account and a project on the platform. I got the Cypress Token, which I added as `CYPRESS_RECORD_KEY` in my GitHub Actions workflow. This allowed Cypress to upload test logs, screenshots, and videos to the Cypress Cloud dashboard for easier debugging. With this setup, I could monitor test history and quickly identify any failures after each deployment.

---

## **4. Results**
The implementation of this architecture has resulted in a **highly reliable, secure, and scalable personal website**. Using **Cypress**, I conducted end-to-end tests to validate critical functionalities, including the visitor count, custom domain with HTTPS, API Gateway integration, and other site components, ensuring everything works as expected. Screenshots of the test results and videos demonstrating the functionality are included below. The combination of serverless components (Lambda, API Gateway, DynamoDB), global content delivery via CloudFront, and robust security measures (DNSSEC, AWS WAF, HTTPS) ensures a performant, secure, and cost-efficient solution.

![Result-Page](https://github.com/Fidelisesq/AWS-Cloud-Resume/blob/main/Images%2BVideos/Result-page1.png)

### A quick run down of the resume page

---

## **5. Conclusion & Lessons Learnt**

This project demonstrates how to build a scalable, secure, and cost-efficient serverless resume website on AWS. By leveraging Terraform for infrastructure as code and GitHub Actions for CI/CD, the entire deployment process is automated and reproducible. 

The use of serverless technologies ensures minimal operational overhead, while monitoring and alerting systems provide visibility into the system’s health. This project reinforced the importance of automation, security, and monitoring in cloud deployments. 

Overcoming challenges with API integrations, Terraform state management, and Lambda execution improved my troubleshooting skills and deepened my understanding of AWS services.
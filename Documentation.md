# **Hosting a Serverless Resume Website on AWS with Terraform and CI/CD**

In this blog post, I’ll walk you through how I implemented a serverless resume website hosted on AWS. The project leverages AWS services like S3, CloudFront, Lambda, DynamoDB, API Gateway, and AWS WAF, all deployed and managed using Terraform in a CI/CD pipeline powered by GitHub. This setup ensures high availability, scalability, and security while maintaining cost efficiency.

---

## **Project Overview**

The goal of this project was to enhance the accessibility and visibility of my resume by hosting it as a responsive website. The website is built using serverless technologies, ensuring minimal operational overhead and maximum scalability. Here’s a high-level breakdown of the architecture:

1. **Frontend**: A static HTML resume hosted on **Amazon S3** and served via **CloudFront** for global content delivery.
2. **Backend**: A serverless API built with **AWS Lambda** and **API Gateway** to handle dynamic functionality (e.g., visitor counter).
3. **Database**: **DynamoDB** to store and retrieve data (e.g., visitor counts).
4. **Security**: **AWS WAF** to protect the website from common web exploits.
5. **DNS and DNSSEC**: **Route 53** for DNS management and DNSSEC for enhanced security.
6. **Monitoring and Alerts**: **CloudWatch**, **SNS**, **PagerDuty**, and **Slack** for monitoring and notifications.
7. **Infrastructure as Code**: **Terraform** to define and provision all AWS resources.
8. **CI/CD**: Automated deployment pipeline using **GitHub Actions**.

---

## **Terraform Configuration**

The entire infrastructure is defined using Terraform, ensuring reproducibility and scalability. Below is a detailed explanation of the Terraform configuration.

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
- **CORS**: Allows cross-origin requests from the custom domain.
- **Bucket Policy**: Restricts access to the bucket, allowing only CloudFront to serve the content.

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
```

- **Lambda Function**: Handles the logic for incrementing and retrieving visitor counts.
- **Environment Variables**: Passes the DynamoDB table name to the Lambda function.

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

- **DynamoDB Table**: Stores the visitor count with a primary key `id`.

#### **API Gateway**

```hcl
# REST API Resource
resource "aws_api_gateway_rest_api" "cloud_resume_api" {
  name        = "CloudResumeAPI"
  description = "API for visitor counter"
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
```

- **API Gateway**: Exposes the Lambda function as a REST API.
- **Integration**: Connects the API Gateway to the Lambda function.

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

- **CloudWatch Alarms**: Monitors API Gateway and Lambda for errors and latency.

#### **SNS Topic for Notifications**

```hcl
# SNS topic resource for notifications
resource "aws_sns_topic" "api_alerts" {
  name = "CloudResumeAlerts"
}
```

- **SNS Topic**: Centralized notification system for alerts.

#### **PagerDuty Integration**

```hcl
# Lambda function for PagerDuty integration
resource "aws_lambda_function" "lambda_to_pagerduty" {
  filename         = "lambda_to_pagerduty.zip"
  function_name    = "lambda_to_pagerduty"
  role             = aws_iam_role.sns_to_pagerduty_lambda_role.arn
  handler          = "lambda_to_pagerduty.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("lambda_to_pagerduty.zip")

  environment {
    variables = {
      PAGERDUTY_SECRET_ARN = aws_secretsmanager_secret.pagerduty_integration_url.arn
    }
  }
}
```

- **PagerDuty Integration**: Sends alerts to PagerDuty for critical issues.

#### **Slack Integration**

```hcl
# Lambda function for Slack integration
resource "aws_lambda_function" "sns_to_slack" {
  filename      = "lambda_to_slack.zip"
  function_name = "SNS-to-Slack"
  role          = aws_iam_role.sns_to_slack_lambda_role.arn
  handler       = "lambda_to_slack.lambda_handler"
  runtime       = "python3.9"
  timeout       = 10

  environment {
    variables = {
      SLACK_WEBHOOK_SECRET_NAME = aws_secretsmanager_secret.slack_webhook_url.name
    }
  }
}
```

- **Slack Integration**: Sends notifications to a Slack channel for non-critical alerts.

---

### **4. Security: AWS WAF**

The website is protected by AWS WAF to prevent common web exploits.

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

- **AWS WAF**: Protects the website from DDoS attacks and other web exploits.

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

---
---

### **6. Automated Testing with Cypress**

To ensure the website functions as expected after deployment, I implemented automated end-to-end (E2E) tests using **Cypress**. These tests are triggered automatically after a successful infrastructure deployment, ensuring that the website is not only deployed but also fully functional.

#### **Cypress Workflow**

The Cypress tests are executed in a separate GitHub Actions workflow that runs after the `Deploy Infrastructure` workflow completes successfully. Here’s how it works:

1. **Pre-Check Step**:
   - The workflow first checks if the `infrastructure-deployment` job in the `Deploy Infrastructure` workflow succeeded.
   - If the deployment was successful, the Cypress tests are executed.

2. **Cypress Execution**:
   - The workflow sets up Node.js, installs dependencies, and runs the Cypress tests.
   - The tests wait for the website to be available at `https://fidelis-resume.fozdigitalz.com/` before running.
   - Test results are recorded and can be viewed in the Cypress Dashboard.

```yaml
name: Cypress Tests

on:
  workflow_run:
    workflows: ["Deploy Infrastructure"]
    types:
      - completed

jobs:
  pre-check:
    runs-on: ubuntu-latest
    outputs:
      should_run: ${{ steps.check-jobs.outputs.deploy_succeeded }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install GitHub CLI
        run: |
          sudo apt-get update
          sudo apt-get install -y gh

      - name: Get Workflow Run Jobs
        id: check-jobs
        run: |
          run_id=${{ github.event.workflow_run.id }}
          repo=${{ github.repository }}
          jobs=$(gh api repos/$repo/actions/runs/$run_id/jobs --jq '.jobs[] | select(.name == "infrastructure-deployment") | .conclusion')
          echo "Job conclusion: $jobs"

          if [[ "$jobs" == "success" ]]; then
            echo "deploy_succeeded=true" >> $GITHUB_OUTPUT
          else
            echo "deploy_succeeded=false" >> $GITHUB_OUTPUT
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  cypress-run:
    runs-on: ubuntu-latest
    needs: pre-check
    if: needs.pre-check.outputs.should_run == 'true'
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

- **Pre-Check**: Ensures that the Cypress tests only run if the infrastructure deployment was successful.
- **Cypress Tests**: Validates the functionality of the website, including the visitor counter and overall responsiveness.
- **Test Recording**: Test results are recorded in the Cypress Dashboard for further analysis.
---

## **Conclusion**

This project demonstrates how to build a scalable, secure, and cost-efficient serverless resume website on AWS. By leveraging Terraform for infrastructure as code and GitHub Actions for CI/CD, the entire deployment process is automated and reproducible. The use of serverless technologies ensures minimal operational overhead, while monitoring and alerting systems provide visibility into the system’s health.


import json
import os
import urllib.request
import boto3
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_slack_webhook_url():
    secret_name = os.environ.get("SLACK_WEBHOOK_SECRET_NAME")  # Get secret name from environment variables
    region_name = os.environ.get("AWS_REGION")

    # Create a Secrets Manager client
    client = boto3.client("secretsmanager", region_name=region_name)

    try:
        logger.info(f"Fetching Slack webhook secret: {secret_name}")
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
        secret = get_secret_value_response["SecretString"]
        secret_dict = json.loads(secret)
        return secret_dict["slack_webhook_url"]
    except Exception as e:
        logger.error(f"Error retrieving secret: {e}")
        raise e

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")  # Log the full event

    try:
        slack_webhook_url = get_slack_webhook_url()
        logger.info(f"Slack Webhook URL retrieved successfully.")

        # Extract SNS message
        message = event["Records"][0]["Sns"]["Message"]
        logger.info(f"SNS Message: {message}")

        payload = {"text": f"AWS Alert: {message}"}

        req = urllib.request.Request(
            slack_webhook_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )

        response = urllib.request.urlopen(req)
        response_body = response.read().decode()

        logger.info(f"Slack response: {response_body}")

        return {
            "statusCode": response.getcode(),
            "body": response_body
        }

    except Exception as e:
        logger.error(f"Error in lambda_handler: {e}")
        return {
            "statusCode": 500,
            "body": f"Error: {str(e)}"
        }

import json
import os
import urllib.request
import boto3

def get_slack_webhook_url():
    secret_name = os.environ["SLACK_WEBHOOK_SECRET_NAME"]  # Get secret name from environment variables
    region_name = os.environ["AWS_REGION"]

    # Create a Secrets Manager client
    client = boto3.client("secretsmanager", region_name=region_name)

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        raise e

    # Decrypts secret using the associated KMS key
    secret = get_secret_value_response["SecretString"]
    secret_dict = json.loads(secret)
    return secret_dict["slack_webhook_url"]

def lambda_handler(event, context):
    slack_webhook_url = get_slack_webhook_url()

    message = event["Records"][0]["Sns"]["Message"]
    payload = {
        "text": f"AWS Alert: {message}"
    }

    req = urllib.request.Request(
        slack_webhook_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    response = urllib.request.urlopen(req)
    
    return {
        "statusCode": response.getcode(),
        "body": response.read().decode()
    }

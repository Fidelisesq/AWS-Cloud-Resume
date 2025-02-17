import json
import requests
import boto3
import os  # Import os to access environment variables

# Initialize clients
secrets_client = boto3.client('secretsmanager')

def lambda_handler(event, context):
    # Retrieve the PagerDuty Integration URL from Secrets Manager using environment variable for secret ARN
    secret_name = os.environ['PAGERDUTY_SECRET_ARN']
    region_name = "us-east-1"
    
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        secret_dict = json.loads(response['SecretString'])
        pagerduty_url = secret_dict['pagerduty_integration_url']
        integration_key = pagerduty_url.split('/')[4]  # Extract the integration key
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        raise e

    # Parse SNS message
    message = event['Records'][0]['Sns']['Message']

    # Prepare the payload to send to PagerDuty
    payload = {
        "payload": {
            "summary": message,
            "source": "AWS Lambda",
            "severity": "critical"  # Adjust severity if needed
        },
        "routing_key": integration_key,  # Use the integration key here
        "event_action": "trigger"
    }

    headers = {
        'Content-Type': 'application/json'
    }

    # Send the payload to PagerDuty
    response = requests.post('https://events.pagerduty.com/v2/enqueue', headers=headers, data=json.dumps(payload))

    if response.status_code == 202:
        print("Successfully sent event to PagerDuty.")
    else:
        print(f"Failed to send event to PagerDuty. Status code: {response.status_code}")
        print(response.text)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Notification processed successfully')
    }

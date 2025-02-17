import json
import requests
import boto3

# Initialize clients
secrets_client = boto3.client('secretsmanager')

def lambda_handler(event, context):
    # Retrieve the PagerDuty Integration URL from Secrets Manager
    secret_name = "pagerduty_integration_url"
    region_name = "us-east-1"
    
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        pagerduty_url = response['SecretString']  # The integration URL
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
            "severity": "critical"  # You can adjust severity as per your needs
        },
        "routing_key": pagerduty_url,
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

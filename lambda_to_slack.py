import json
import urllib.request
import os

def lambda_handler(event, context):
    slack_webhook_url = os.environ['SLACK_WEBHOOK_URL']

    message = event['Records'][0]['Sns']['Message']
    payload = {
        "text": f"AWS Alert: {message}"
    }

    req = urllib.request.Request(
        slack_webhook_url,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )

    response = urllib.request.urlopen(req)
    
    return {
        'statusCode': response.getcode(),
        'body': response.read().decode()
    }

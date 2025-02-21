import json
import boto3
import os
import hashlib
from decimal import Decimal
from datetime import datetime, timedelta

# Initialize the DynamoDB client
dynamodb = boto3.resource('dynamodb')

# Fetch table name from environment variables
table_name = os.environ['DYNAMODB_TABLE']
table = dynamodb.Table(table_name)

# Helper function to handle Decimal serialization
def decimal_to_native(obj):
    if isinstance(obj, Decimal):
        return int(obj) if obj % 1 == 0 else float(obj)
    raise TypeError

def hash_ip(ip_address):
    return hashlib.sha256(ip_address.encode('utf-8')).hexdigest()

def lambda_handler(event, context):
    key = {"id": "counter"}
    
    # **Trigger a Forced Lambda Error (API Gateway 5XX Error)**
    if 'test_error' in event.get('queryStringParameters', {}):
        raise Exception("Forced API Gateway 5XX Error for testing")

    try:
        visitor_ip = event['requestContext']['identity']['sourceIp']
        visitor_hash = hash_ip(visitor_ip)  # Hash the IP address
        visitor_key = {"id": f"visitor_{visitor_hash}"}
        
        # Fetch the visitor's last visit time
        visitor_response = table.get_item(Key=visitor_key)
        last_visit = visitor_response.get('Item', {}).get('lastVisit', None)
        now = datetime.utcnow()
        
        increment_count = False
        
        if last_visit:
            last_visit = datetime.strptime(last_visit, '%Y-%m-%dT%H:%M:%SZ')
            if now - last_visit < timedelta(minutes=2):
                # Fetch the current counter value
                counter_response = table.get_item(Key=key)
                count = counter_response.get('Item', {}).get('count', 0)
                return {
                    "statusCode": 200,
                    "headers": {
                        "Access-Control-Allow-Origin": "https://fidelis-resume.fozdigitalz.com",
                        "Access-Control-Allow-Methods": "GET, OPTIONS",
                        "Access-Control-Allow-Headers": "Content-Type"
                    },
                    "body": json.dumps({ "count": count }, default=decimal_to_native)
                }
            else:
                increment_count = True
        else:
            increment_count = True
        
        if increment_count:
            # Fetch the current counter value
            response = table.get_item(Key=key)
            count = response.get('Item', {}).get('count', 0)
            
            if isinstance(count, Decimal):
                count = int(count)
            
            # Increment the counter
            count += 1
            
            # Update the counter and visitor's last visit time in the database
            table.put_item(Item={"id": "counter", "count": count})
            table.put_item(Item={"id": f"visitor_{visitor_hash}", "lastVisit": now.strftime('%Y-%m-%dT%H:%M:%SZ')})
            
            # Return the updated count with CORS headers
            return {
                "statusCode": 200,
                "headers": {
                    "Access-Control-Allow-Origin": "https://fidelis-resume.fozdigitalz.com",
                    "Access-Control-Allow-Methods": "GET, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type"
                },
                "body": json.dumps({ "count": count }, default=decimal_to_native)
            }
    
    except Exception as e:
        print("Error updating visitor count:", str(e))
        
        # **Simulate a Lambda Function Error**
        if 'test_lambda_error' in event.get('queryStringParameters', {}):
            return 1 / 0  # This will cause a ZeroDivisionError
        
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "https://fidelis-resume.fozdigitalz.com",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({ "error": "Internal Server Error" })
        }

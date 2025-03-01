import json
import boto3
import os
import hashlib  # ✅ FIXED: Import hashlib
from decimal import Decimal
from datetime import datetime, timedelta

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table_name = os.environ['DYNAMODB_TABLE']
table = dynamodb.Table(table_name)

# Helper function for Decimal serialization
def decimal_to_native(obj):
    if isinstance(obj, Decimal):
        return int(obj) if obj % 1 == 0 else float(obj)
    raise TypeError

def hash_ip(ip_address):
    return hashlib.sha256(ip_address.encode('utf-8')).hexdigest()

def lambda_handler(event, context):
    key = {"id": "counter"}

    # ✅ Get headers safely (avoid KeyError)
    headers = event.get('headers', {})
    visitor_ip = headers.get('X-Forwarded-For', 'Unknown').split(',')[0].strip()

    # ✅ Debugging log
    print(f"Visitor IP: {visitor_ip}")

    if visitor_ip == "Unknown":
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing visitor IP"})
        }

    # ✅ Hash IP for privacy
    visitor_hash = hash_ip(visitor_ip)
    visitor_key = {"id": f"visitor_{visitor_hash}"}

    try:
        # Fetch visitor's last visit time
        visitor_response = table.get_item(Key=visitor_key)
        last_visit = visitor_response.get('Item', {}).get('lastVisit', None)
        now = datetime.utcnow()
        
        increment_count = False
        
        if last_visit:
            last_visit = datetime.strptime(last_visit, '%Y-%m-%dT%H:%M:%SZ')
            if now - last_visit < timedelta(minutes=2):
                # Fetch current counter value
                counter_response = table.get_item(Key=key)
                count = counter_response.get('Item', {}).get('count', 0)
                return {
                    "statusCode": 200,
                    "headers": {
                        "Access-Control-Allow-Origin": "https://fidelis-resume.fozdigitalz.com",
                        "Access-Control-Allow-Methods": "GET, OPTIONS",
                        "Access-Control-Allow-Headers": "Content-Type"
                    },
                    "body": json.dumps({"count": count}, default=decimal_to_native)
                }
            else:
                increment_count = True
        else:
            increment_count = True
        
        if increment_count:
            # ✅ Increment counter correctly
            update_response = table.update_item(
                Key={"id": "counter"},
                UpdateExpression="SET count = if_not_exists(count, :start) + :inc",
                ExpressionAttributeValues={":start": 0, ":inc": 1},
                ReturnValues="UPDATED_NEW"
            )

            # ✅ Store visitor's last visit time
            table.put_item(Item={"id": f"visitor_{visitor_hash}", "lastVisit": now.strftime('%Y-%m-%dT%H:%M:%SZ")})
            
            # ✅ Fetch updated counter
            new_count = update_response['Attributes']['count']

            return {
                "statusCode": 200,
                "headers": {
                    "Access-Control-Allow-Origin": "https://fidelis-resume.fozdigitalz.com",
                    "Access-Control-Allow-Methods": "GET, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type"
                },
                "body": json.dumps({"count": new_count}, default=decimal_to_native)
            }
    
    except Exception as e:
        print("Error updating visitor count:", str(e))
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "https://fidelis-resume.fozdigitalz.com",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({"error": "Internal Server Error"})
        }

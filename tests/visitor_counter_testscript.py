import json
import boto3
import os
import hashlib
from decimal import Decimal
from datetime import datetime
from moto import mock_dynamodb  # Updated import
import pytest

# Mock the environment variable for DynamoDB table name
os.environ['DYNAMODB_TABLE'] = 'VisitorCounterTable'

# Import the Lambda function
from visitor_counter_lambda import lambda_handler

# Function to hash visitor IP (same as in Lambda)
def hash_ip(ip_address):
    return hashlib.sha256(ip_address.encode('utf-8')).hexdigest()

@pytest.fixture
def setup_dynamodb():
    """ Set up a mock DynamoDB table for testing """
    with mock_dynamodb():  # Updated mock
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        table_name = os.environ['DYNAMODB_TABLE']

        # Create the mock table
        table = dynamodb.create_table(
            TableName=table_name,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST"
        )

        # Insert initial data
        table.put_item(Item={"id": "counter", "count": Decimal(0)})
        yield table  # Provide the table to tests

def test_lambda_handler(setup_dynamodb):
    """ Test the Lambda function with a simulated API Gateway request """
    table = setup_dynamodb  # Get mock DynamoDB table
    test_ip = "192.168.1.1"
    visitor_hash = hash_ip(test_ip)

    # Simulate an API Gateway event
    event = {
        "requestContext": {
            "identity": {"sourceIp": test_ip}
        }
    }

    # Run the Lambda function
    response = lambda_handler(event, None)

    # Validate response
    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert "count" in body

    # Fetch updated count from DynamoDB
    updated_item = table.get_item(Key={"id": "counter"})
    assert updated_item["Item"]["count"] == 1

    print("Test Passed. Visitor Count:", body["count"])
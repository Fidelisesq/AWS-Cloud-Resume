def lambda_handler(event, context):
    key = {"id": "counter"}

    # ✅ Extract real visitor IP from API Gateway headers
    visitor_ip = event['headers'].get('X-Forwarded-For', '').split(',')[0].strip()
    
    # ✅ Hash the IP for privacy
    visitor_hash = hashlib.sha256(visitor_ip.encode('utf-8')).hexdigest()
    visitor_key = {"id": f"visitor_{visitor_hash}"}
    
    try:
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
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "https://fidelis-resume.fozdigitalz.com",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({ "error": "Internal Server Error" })
        }

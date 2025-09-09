#!/usr/bin/env python3
import requests
import json
import sys

def send_fcm_push(server_key, fcm_token, title="KILLED STATE TEST", body="Testing if FCM works when app is killed"):
    """
    Send a test FCM push notification - DATA ONLY for killed state
    """
    url = "https://fcm.googleapis.com/fcm/send"
    
    headers = {
        "Authorization": f"key={server_key}",
        "Content-Type": "application/json"
    }
    
    # CRITICAL: Data-only message with high priority for killed state
    payload = {
        "to": fcm_token,
        "priority": "high",
        "data": {
            "call_id": "test_killed_state_123",
            "caller_name": "Test Caller",
            "caller_number": "+1234567890",
            "type": "incoming_call",
            "title": title,
            "body": body
        },
        "android": {
            "priority": "high",
            "ttl": "600s"
        }
    }
    
    print(f"🚀 Sending KILLED-STATE FCM test to: {fcm_token[:20]}...")
    print(f"📦 Data-only payload (no notification): {json.dumps(payload, indent=2)}")
    
    response = requests.post(url, headers=headers, json=payload)
    
    print(f"📊 Response Status: {response.status_code}")
    print(f"📄 Response Body: {response.text}")
    
    if response.status_code == 200:
        print("✅ FCM request successful! Check device for background handler logs...")
    else:
        print("❌ FCM request failed!")
    
    return response.status_code == 200

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 test_fcm_push.py <SERVER_KEY> <FCM_TOKEN>")
        print("\nTo get your Firebase server key:")
        print("1. Go to Firebase Console -> Project Settings -> Cloud Messaging")
        print("2. Copy the 'Server key'")
        print("\nTo get FCM token, check the app logs when it starts")
        sys.exit(1)
    
    server_key = sys.argv[1]
    fcm_token = sys.argv[2]
    
    success = send_fcm_push(server_key, fcm_token)
    if success:
        print("\n✅ FCM push sent successfully!")
        print("Now check if notification appears and app starts...")
    else:
        print("\n❌ FCM push failed!")

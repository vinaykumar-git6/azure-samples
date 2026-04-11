"""
Simple MQTT Sender for Azure Event Grid

Sends test messages to Azure Event Grid using MQTT protocol with JWT (Azure AD) authentication.
"""

import os
import json
import time
from datetime import datetime
from dotenv import load_dotenv
import paho.mqtt.client as mqtt
from azure.identity import DefaultAzureCredential, ClientSecretCredential

# Load environment variables
load_dotenv()

# Configuration
EVENTGRID_HOSTNAME = os.getenv("EVENTGRID_HOSTNAME")
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "sensors/telemetry")
MQTT_CLIENT_ID = os.getenv("MQTT_CLIENT_ID", "sensor-app-001")
MQTT_PORT = int(os.getenv("MQTT_PORT", "8883"))

# Azure AD Configuration for JWT authentication
AZURE_CLIENT_ID = os.getenv("AZURE_CLIENT_ID")
AZURE_TENANT_ID = os.getenv("AZURE_TENANT_ID")
AZURE_CLIENT_SECRET = os.getenv("AZURE_CLIENT_SECRET")




def get_azure_ad_token():
    """Get Azure AD access token for Event Grid MQTT authentication."""
    scope = "https://eventgrid.azure.net/.default"
    
    try:
        # Use ClientSecretCredential if credentials provided, else DefaultAzureCredential
        if AZURE_CLIENT_ID and AZURE_TENANT_ID and AZURE_CLIENT_SECRET:
            print("🔑 Using ClientSecretCredential (Service Principal)")
            credential = ClientSecretCredential(
                tenant_id=AZURE_TENANT_ID,
                client_id=AZURE_CLIENT_ID,
                client_secret=AZURE_CLIENT_SECRET
            )
        else:
            print("🔑 Using DefaultAzureCredential (az login, managed identity)")
            credential = DefaultAzureCredential()
        
        token = credential.get_token(scope)
        print(f"✅ Access token obtained (expires: {datetime.fromtimestamp(token.expires_on)})")
        return token.token
    except Exception as e:
        print(f"❌ Failed to get Azure AD token: {e}")
        raise


def on_connect(client, userdata, flags, rc, properties=None):
    """Callback when connected to MQTT broker."""
    if rc == 0:
        print("✅ Connected to Azure Event Grid MQTT broker")
    else:
        print(f"❌ Connection failed with code: {rc}")
        error_messages = {
            1: "Connection refused - incorrect protocol version",
            2: "Connection refused - invalid client identifier",
            3: "Connection refused - server unavailable",
            4: "Connection refused - bad username or password",
            5: "Connection refused - not authorized"
        }
        print(f"   Error: {error_messages.get(rc, 'Unknown error')}")


def on_publish(client, userdata, mid):
    """Callback when message is published."""
    print(f"✅ Message published (message ID: {mid})")


def on_disconnect(client, userdata, rc, properties=None):
    """Callback when disconnected from MQTT broker (MQTT v5)."""
    if rc != 0:
        print(f"⚠️ Unexpected disconnection (code: {rc})")
    else:
        print("✅ Disconnected successfully")


def send_test_messages(num_messages=5):
    """
    Send test messages to Azure Event Hubs via MQTT.
    
    Args:
        num_messages: Number of test messages to send (default 5)
    """
    print("=" * 60)
    print("Azure Event Grid MQTT Sender (JWT Auth)")
    print("=" * 60)
    print(f"Event Grid Host: {EVENTGRID_HOSTNAME}")
    print(f"MQTT Topic: {MQTT_TOPIC}")
    print(f"MQTT Client ID: {MQTT_CLIENT_ID}")
    print(f"Port: {MQTT_PORT}")
    print()
    
    # Get Azure AD access token
    print("🔑 Getting Azure AD access token...")
    access_token = get_azure_ad_token()
    print()
    
    # Create MQTT client with Event Grid client ID
    # For Event Grid, the MQTT client ID must match the registered client name
    client = mqtt.Client(
        client_id=MQTT_CLIENT_ID, 
        protocol=mqtt.MQTTv5,
        transport="tcp"
    )
    
    # Enable detailed logging
    client.enable_logger()
    
    # Set callbacks
    client.on_connect = on_connect
    client.on_publish = on_publish
    client.on_disconnect = on_disconnect
    
    # Configure TLS
    try:
        import ssl
        print(f"🔒 Configuring TLS/SSL...")
        client.tls_set(
            cert_reqs=ssl.CERT_REQUIRED,
            tls_version=ssl.PROTOCOL_TLSv1_2
        )
        print(f"✅ TLS configured")
    except Exception as e:
        print(f"❌ TLS configuration failed: {e}")
        raise
    
    try:
        # Connect to Event Grid with JWT authentication
        print(f"🔌 Connecting to {EVENTGRID_HOSTNAME}:{MQTT_PORT}...")
        print(f"   MQTT Client ID: {MQTT_CLIENT_ID}")
        print(f"   Authentication: OAUTH2-JWT")
        
        # Set connection properties for MQTT v5 with JWT
        from paho.mqtt.properties import Properties
        from paho.mqtt.packettypes import PacketTypes
        
        properties = Properties(PacketTypes.CONNECT)
        properties.AuthenticationMethod = "OAUTH2-JWT"
        properties.AuthenticationData = access_token.encode('utf-8')
        
        client.connect(
            EVENTGRID_HOSTNAME, 
            MQTT_PORT, 
            keepalive=60,
            properties=properties
        )
        
        # Start network loop in background
        client.loop_start()
        
        # Wait for connection with timeout
        print(f"⏳ Waiting for connection...")
        connection_timeout = 10
        start_time = time.time()
        while not client.is_connected() and (time.time() - start_time) < connection_timeout:
            time.sleep(0.5)
        
        if not client.is_connected():
            print(f"❌ Connection timeout after {connection_timeout} seconds")
            print(f"   Possible causes:")
            print(f"   1. Port 8883 is blocked by firewall")
            print(f"   2. MQTT broker is not enabled on Event Hub namespace")
            print(f"   3. Namespace DNS name is incorrect")
            print(f"   4. Network connectivity issues")
            client.loop_stop()
            return
        
        print(f"✅ Connection established")
        time.sleep(1)
        
        # MQTT topic for Event Grid
        topic = MQTT_TOPIC
        
        print(f"📤 Sending {num_messages} test messages...")
        print()
        
        # Send test messages
        for i in range(1, num_messages + 1):
            # Create message payload
            message = {
                "message_id": i,
                "timestamp": datetime.utcnow().isoformat(),
                "sensor_id": f"sensor-{i % 3 + 1}",
                "temperature": 20 + (i * 0.5),
                "humidity": 50 + (i * 2),
                "status": "active"
            }
            
            # Convert to JSON
            payload = json.dumps(message)
            
            # Publish message
            print(f"📨 Sending message {i}/{num_messages}...")
            print(f"   Topic: {topic}")
            print(f"   Payload: {payload}")
            
            result = client.publish(topic, payload, qos=1)
            
            if result.rc == mqtt.MQTT_ERR_SUCCESS:
                print(f"   ✅ Message queued successfully")
            else:
                print(f"   ❌ Failed to queue message (code: {result.rc})")
            
            print()
            
            # Wait between messages
            time.sleep(1)
        
        # Wait for all messages to be published
        print("⏳ Waiting for messages to be published...")
        time.sleep(3)
        
        print()
        print("=" * 60)
        print(f"✅ Successfully sent {num_messages} messages to Event Hub!")
        print("=" * 60)
        
    except Exception as e:
        print(f"❌ Error: {e}")
    
    finally:
        # Cleanup
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    # Validate configuration
    if not all([EVENTGRID_HOSTNAME, MQTT_TOPIC, MQTT_CLIENT_ID]):
        print("❌ Error: Missing configuration!")
        print("Please set all required environment variables in .env file")
        print("Required variables:")
        print("  - EVENTGRID_HOSTNAME")
        print("  - MQTT_TOPIC")
        print("  - MQTT_CLIENT_ID")
        print("\nFor Service Principal authentication:")
        print("  - AZURE_CLIENT_ID")
        print("  - AZURE_TENANT_ID")
        print("  - AZURE_CLIENT_SECRET")
        print("\nNote: Leave Azure credentials empty to use DefaultAzureCredential (az login)")
        exit(1)
    
    # Send test messages
    send_test_messages(num_messages=5)

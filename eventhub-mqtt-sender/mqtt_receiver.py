"""
Simple MQTT Receiver for Azure Event Grid

Subscribes to topics on Azure Event Grid using MQTT protocol with JWT (Azure AD) authentication.
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
MQTT_CLIENT_ID = os.getenv("MQTT_CLIENT_ID", "sensor-app-jwt") + "-receiver"  # Different client ID
MQTT_PORT = int(os.getenv("MQTT_PORT", "8883"))

# Azure AD Configuration for JWT authentication
AZURE_CLIENT_ID = os.getenv("AZURE_CLIENT_ID")
AZURE_TENANT_ID = os.getenv("AZURE_TENANT_ID")
AZURE_CLIENT_SECRET = os.getenv("AZURE_CLIENT_SECRET")

# Message counter
message_count = 0


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
        
        # Subscribe to topic with wildcard
        subscribe_topic = "sensors/#"  # Subscribe to all sensors topics
        print(f"📥 Subscribing to topic: {subscribe_topic}")
        result, mid = client.subscribe(subscribe_topic, qos=1)
        
        if result == mqtt.MQTT_ERR_SUCCESS:
            print(f"✅ Subscription request sent (message ID: {mid})")
        else:
            print(f"❌ Subscription failed (code: {result})")
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


def on_subscribe(client, userdata, mid, granted_qos, properties=None):
    """Callback when subscription is confirmed."""
    print(f"✅ Subscription confirmed (message ID: {mid}, QoS: {granted_qos})")
    print()
    print("=" * 60)
    print("🎧 Listening for messages... (Press Ctrl+C to stop)")
    print("=" * 60)
    print()


def on_message(client, userdata, msg):
    """Callback when message is received."""
    global message_count
    message_count += 1
    
    print(f"📬 Message #{message_count} received")
    print(f"   Topic: {msg.topic}")
    print(f"   QoS: {msg.qos}")
    print(f"   Retain: {msg.retain}")
    print(f"   Timestamp: {datetime.now().isoformat()}")
    
    try:
        # Try to parse as JSON
        payload = json.loads(msg.payload.decode('utf-8'))
        print(f"   Payload (JSON):")
        for key, value in payload.items():
            print(f"      {key}: {value}")
    except json.JSONDecodeError:
        # If not JSON, print as string
        print(f"   Payload (text): {msg.payload.decode('utf-8')}")
    except Exception as e:
        # If decoding fails, print raw bytes
        print(f"   Payload (raw): {msg.payload}")
    
    print()


def on_disconnect(client, userdata, rc, properties=None):
    """Callback when disconnected from MQTT broker (MQTT v5)."""
    if rc != 0:
        print(f"⚠️ Unexpected disconnection (code: {rc})")
    else:
        print("✅ Disconnected successfully")


def receive_messages():
    """
    Subscribe to MQTT topic and receive messages from Azure Event Grid.
    """
    print("=" * 60)
    print("Azure Event Grid MQTT Receiver (JWT Auth)")
    print("=" * 60)
    print(f"Event Grid Host: {EVENTGRID_HOSTNAME}")
    print(f"MQTT Topic Filter: sensors/#")
    print(f"MQTT Client ID: {MQTT_CLIENT_ID}")
    print(f"Port: {MQTT_PORT}")
    print()
    
    # Get Azure AD access token
    print("🔑 Getting Azure AD access token...")
    access_token = get_azure_ad_token()
    print()
    
    # Create MQTT client with unique receiver client ID
    client = mqtt.Client(
        client_id=MQTT_CLIENT_ID, 
        protocol=mqtt.MQTTv5,
        transport="tcp"
    )
    
    # Enable detailed logging
    client.enable_logger()
    
    # Set callbacks
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_subscribe = on_subscribe
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
            print(f"   2. MQTT broker is not enabled on Event Grid namespace")
            print(f"   3. Namespace DNS name is incorrect")
            print(f"   4. Network connectivity issues")
            client.loop_stop()
            return
        
        print(f"✅ Connection established")
        time.sleep(2)  # Wait for subscription to complete
        
        # Keep running until interrupted
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print()
            print("=" * 60)
            print(f"📊 Total messages received: {message_count}")
            print("=" * 60)
            print("👋 Shutting down...")
        
    except Exception as e:
        print(f"❌ Error: {e}")
    
    finally:
        # Cleanup
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    # Validate configuration
    if not all([EVENTGRID_HOSTNAME, MQTT_CLIENT_ID]):
        print("❌ Error: Missing configuration!")
        print("Please set all required environment variables in .env file")
        print("Required variables:")
        print("  - EVENTGRID_HOSTNAME")
        print("  - MQTT_CLIENT_ID")
        print("\nFor Service Principal authentication:")
        print("  - AZURE_CLIENT_ID")
        print("  - AZURE_TENANT_ID")
        print("  - AZURE_CLIENT_SECRET")
        print("\nNote: Leave Azure credentials empty to use DefaultAzureCredential (az login)")
        exit(1)
    
    # Start receiving messages
    receive_messages()

"""
Simple Event Producer for Azure Event Hubs

Sends test messages to Azure Event Hubs with Azure AD authentication.
Uses azure-eventhub SDK (simpler than Kafka protocol).
"""

import os
import json
from datetime import datetime
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.eventhub import EventHubProducerClient, EventData

# Load environment variables
load_dotenv()

# Configuration
EVENTHUB_NAMESPACE = os.getenv("EVENTHUB_NAMESPACE")
EVENTHUB_NAME = os.getenv("EVENTHUB_NAME")
AZURE_CLIENT_ID = os.getenv("AZURE_CLIENT_ID")
AZURE_TENANT_ID = os.getenv("AZURE_TENANT_ID")
AZURE_CLIENT_SECRET = os.getenv("AZURE_CLIENT_SECRET")

# Unset empty credentials
if AZURE_CLIENT_SECRET == "" or AZURE_CLIENT_SECRET is None:
    if "AZURE_CLIENT_SECRET" in os.environ:
        del os.environ["AZURE_CLIENT_SECRET"]
    AZURE_CLIENT_SECRET = None
    
if AZURE_TENANT_ID == "your-tenant-id-here" or AZURE_TENANT_ID == "":
    if "AZURE_TENANT_ID" in os.environ:
        del os.environ["AZURE_TENANT_ID"]
    AZURE_TENANT_ID = None





def send_messages(num_messages=5):
    """Send test messages to Event Hubs."""
    
    print("=" * 60)
    print("Azure Event Hubs Producer (Azure AD Auth)")
    print("=" * 60)
    print(f"Namespace: {EVENTHUB_NAMESPACE}")
    print(f"Event Hub: {EVENTHUB_NAME}")
    print(f"Client ID: {AZURE_CLIENT_ID}")
    print()
    
    # Create credential
    if AZURE_CLIENT_ID and AZURE_TENANT_ID and AZURE_CLIENT_SECRET:
        print("🔑 Using ClientSecretCredential (Service Principal)")
        credential = ClientSecretCredential(
            tenant_id=AZURE_TENANT_ID,
            client_id=AZURE_CLIENT_ID,
            client_secret=AZURE_CLIENT_SECRET
        )
    else:
        print("� Using DefaultAzureCredential (az login, managed identity, etc.)")
        credential = DefaultAzureCredential()
    
    # Create Event Hub producer client
    fully_qualified_namespace = EVENTHUB_NAMESPACE
    eventhub_name = EVENTHUB_NAME
    
    print(f"🔌 Connecting to Event Hub: {fully_qualified_namespace}/{eventhub_name}")
    
    producer = EventHubProducerClient(
        fully_qualified_namespace=fully_qualified_namespace,
        eventhub_name=eventhub_name,
        credential=credential
    )
    
    print("✅ Connected to Event Hub")
    print()
    
    # Send messages
    print(f"📤 Sending {num_messages} test messages...")
    print()
    
    try:
        # Create a batch with partition key for compacted Event Hub
        # Using a consistent partition key for testing
        event_data_batch = producer.create_batch(partition_key="test-sensor")
        
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
            
            payload = json.dumps(message)
            partition_key = f"sensor-{i % 3 + 1}"
            
            print(f"📨 Message {i}/{num_messages} (key: {partition_key}): {payload}")
            
            # Create event data with partition key (required for compacted Event Hub)
            event_data = EventData(body=payload)
            
            # Add message to batch with partition key
            try:
                event_data_batch.add(event_data)
            except ValueError:
                # Batch is full, send it and create a new one
                producer.send_batch(event_data_batch)
                event_data_batch = producer.create_batch()
                event_data_batch.add(EventData(payload))
        
        # Send the final batch
        if len(event_data_batch) > 0:
            producer.send_batch(event_data_batch)
            print()
            print(f"✅ Sent batch of {len(event_data_batch)} messages")
        
    except Exception as e:
        print(f"❌ Error sending messages: {e}")
        raise
    finally:
        producer.close()
    
    print()
    print("=" * 60)
    print(f"✅ Successfully sent {num_messages} messages to Event Hub!")
    print("=" * 60)


if __name__ == "__main__":
    # Validate configuration
    if not all([EVENTHUB_NAMESPACE, EVENTHUB_NAME, AZURE_CLIENT_ID]):
        print("❌ Error: Missing configuration!")
        print("Please set all required environment variables in .env file")
        print("Required variables:")
        print("  - EVENTHUB_NAMESPACE")
        print("  - EVENTHUB_NAME")
        print("  - AZURE_CLIENT_ID")
        print("\nOptional (for Service Principal auth):")
        print("  - AZURE_TENANT_ID")
        print("  - AZURE_CLIENT_SECRET")
        print("\nOr use 'az login' for interactive authentication")
        exit(1)
    
    # Send test messages
    send_messages(num_messages=5)

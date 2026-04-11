"""
Simple Event Consumer for Azure Event Hubs

Receives messages from Azure Event Hubs with Azure AD authentication.
Uses azure-eventhub SDK (simpler than Kafka protocol).
"""

import os
import json
from datetime import datetime
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.eventhub import EventHubConsumerClient

# Load environment variables
load_dotenv()

# Configuration
EVENTHUB_NAMESPACE = os.getenv("EVENTHUB_NAMESPACE")
EVENTHUB_NAME = os.getenv("EVENTHUB_NAME")
AZURE_CLIENT_ID = os.getenv("AZURE_CLIENT_ID")
AZURE_TENANT_ID = os.getenv("AZURE_TENANT_ID")
AZURE_CLIENT_SECRET = os.getenv("AZURE_CLIENT_SECRET")
CONSUMER_GROUP = os.getenv("CONSUMER_GROUP", "$Default")

# Unset empty credentials
if AZURE_CLIENT_SECRET == "" or AZURE_CLIENT_SECRET is None:
    if "AZURE_CLIENT_SECRET" in os.environ:
        del os.environ["AZURE_CLIENT_SECRET"]
    AZURE_CLIENT_SECRET = None
    
if AZURE_TENANT_ID == "your-tenant-id-here" or AZURE_TENANT_ID == "":
    if "AZURE_TENANT_ID" in os.environ:
        del os.environ["AZURE_TENANT_ID"]
    AZURE_TENANT_ID = None


# Message counter
message_count = 0
max_messages = 10  # Stop after receiving this many messages


def on_event(partition_context, event):
    """
    Callback function called when an event is received.
    
    Args:
        partition_context: Information about the partition
        event: The received event
    """
    global message_count
    message_count += 1
    
    # Decode message body
    body = event.body_as_str()
    
    # Parse JSON if possible
    try:
        data = json.loads(body)
        formatted_body = json.dumps(data, indent=2)
    except:
        formatted_body = body
    
    print(f"\n{'='*60}")
    print(f"📨 Message #{message_count} received")
    print(f"{'='*60}")
    print(f"Partition ID: {partition_context.partition_id}")
    print(f"Offset: {event.offset}")
    print(f"Sequence Number: {event.sequence_number}")
    print(f"Enqueued Time: {event.enqueued_time}")
    
    if event.partition_key:
        print(f"Partition Key: {event.partition_key}")
    
    if event.properties:
        print(f"Properties: {event.properties}")
    
    print(f"\nMessage Body:")
    print(formatted_body)
    
    # Update checkpoint (mark message as processed)
    partition_context.update_checkpoint(event)
    
    # Stop after max_messages
    if message_count >= max_messages:
        print(f"\n{'='*60}")
        print(f"✅ Received {message_count} messages. Stopping consumer...")
        print(f"{'='*60}")
        raise KeyboardInterrupt()


def on_error(partition_context, error):
    """
    Callback function called when an error occurs.
    
    Args:
        partition_context: Information about the partition
        error: The error that occurred
    """
    if partition_context:
        print(f"❌ Error in partition {partition_context.partition_id}: {error}")
    else:
        print(f"❌ Error: {error}")


def on_partition_initialize(partition_context):
    """Called when a partition is initialized."""
    print(f"✅ Partition {partition_context.partition_id} initialized")


def on_partition_close(partition_context, reason):
    """Called when a partition is closed."""
    print(f"⚠️ Partition {partition_context.partition_id} closed: {reason}")


def receive_messages():
    """Receive messages from Event Hubs."""
    
    print("=" * 60)
    print("Azure Event Hubs Consumer (Azure AD Auth)")
    print("=" * 60)
    print(f"Namespace: {EVENTHUB_NAMESPACE}")
    print(f"Event Hub: {EVENTHUB_NAME}")
    print(f"Consumer Group: {CONSUMER_GROUP}")
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
        print("🔑 Using DefaultAzureCredential (az login, managed identity, etc.)")
        credential = DefaultAzureCredential()
    
    # Create Event Hub consumer client
    fully_qualified_namespace = EVENTHUB_NAMESPACE
    eventhub_name = EVENTHUB_NAME
    
    print(f"🔌 Connecting to Event Hub: {fully_qualified_namespace}/{eventhub_name}")
    
    consumer = EventHubConsumerClient(
        fully_qualified_namespace=fully_qualified_namespace,
        eventhub_name=eventhub_name,
        consumer_group=CONSUMER_GROUP,
        credential=credential
    )
    
    print("✅ Connected to Event Hub")
    print()
    print(f"📥 Listening for messages (max: {max_messages})...")
    print("Press Ctrl+C to stop")
    print("=" * 60)
    
    try:
        # Start receiving
        # starting_position="-1" means start from the beginning
        # For latest messages only, use starting_position="@latest"
        consumer.receive(
            on_event=on_event,
            on_error=on_error,
            on_partition_initialize=on_partition_initialize,
            on_partition_close=on_partition_close,
            starting_position="-1",  # Start from beginning
        )
    except KeyboardInterrupt:
        print("\n\n🛑 Stopping consumer...")
    except Exception as e:
        print(f"\n❌ Error receiving messages: {e}")
        raise
    finally:
        consumer.close()
        print("✅ Consumer closed")
    
    print()
    print("=" * 60)
    print(f"✅ Total messages received: {message_count}")
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
        print("\nOptional:")
        print("  - CONSUMER_GROUP (default: $Default)")
        print("  - AZURE_TENANT_ID")
        print("  - AZURE_CLIENT_SECRET")
        print("\nOr use 'az login' for interactive authentication")
        exit(1)
    
    # Receive messages
    receive_messages()

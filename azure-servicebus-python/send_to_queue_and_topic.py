"""
Azure Service Bus Message Sender - Queue and Topic

Sends dummy messages to:
- Service Bus: svcdemoprmgeorepl
- Resource Group: apim-vinay-rg
- Queue: first_q
- Topic: sensordata
"""

import json
import random
from datetime import datetime
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.identity import AzureCliCredential

# Configuration
SERVICEBUS_NAMESPACE = "svcdemoprmgeorepl"
SERVICEBUS_FULLY_QUALIFIED_NAMESPACE = f"{SERVICEBUS_NAMESPACE}.servicebus.windows.net"
QUEUE_NAME = "first_q"
TOPIC_NAME = "sensordata"


def get_servicebus_client() -> ServiceBusClient:
    """Create and return a Service Bus client using Azure CLI credentials."""
    credential = AzureCliCredential()
    return ServiceBusClient(
        fully_qualified_namespace=SERVICEBUS_FULLY_QUALIFIED_NAMESPACE,
        credential=credential
    )


def generate_dummy_queue_message() -> dict:
    """Generate a dummy message for the queue."""
    return {
        "messageId": f"msg-{random.randint(1000, 9999)}",
        "timestamp": datetime.utcnow().isoformat(),
        "source": "queue-sender",
        "payload": {
            "action": random.choice(["create", "update", "delete"]),
            "resource": f"resource-{random.randint(1, 100)}",
            "priority": random.choice(["low", "medium", "high"])
        }
    }


def generate_dummy_sensor_message() -> dict:
    """Generate a dummy sensor data message for the topic."""
    return {
        "sensorId": f"sensor-{random.randint(1, 50)}",
        "timestamp": datetime.utcnow().isoformat(),
        "location": random.choice(["building-A", "building-B", "building-C"]),
        "readings": {
            "temperature": round(random.uniform(20.0, 35.0), 2),
            "humidity": round(random.uniform(30.0, 80.0), 2),
            "pressure": round(random.uniform(1000.0, 1025.0), 2)
        },
        "status": random.choice(["online", "degraded", "maintenance"])
    }


def send_messages_to_queue(client: ServiceBusClient, count: int = 5) -> None:
    """Send dummy messages to the queue."""
    print(f"\n{'='*50}")
    print(f"Sending {count} messages to Queue: {QUEUE_NAME}")
    print(f"{'='*50}")
    
    with client.get_queue_sender(queue_name=QUEUE_NAME) as sender:
        for i in range(count):
            message_data = generate_dummy_queue_message()
            message = ServiceBusMessage(
                body=json.dumps(message_data),
                content_type="application/json",
                subject=f"QueueMessage-{i+1}"
            )
            sender.send_messages(message)
            print(f"✓ Sent message {i+1}: {message_data['messageId']}")
    
    print(f"\nSuccessfully sent {count} messages to queue '{QUEUE_NAME}'")


def send_messages_to_topic(client: ServiceBusClient, count: int = 5) -> None:
    """Send dummy sensor data messages to the topic."""
    print(f"\n{'='*50}")
    print(f"Sending {count} messages to Topic: {TOPIC_NAME}")
    print(f"{'='*50}")
    
    with client.get_topic_sender(topic_name=TOPIC_NAME) as sender:
        for i in range(count):
            message_data = generate_dummy_sensor_message()
            message = ServiceBusMessage(
                body=json.dumps(message_data),
                content_type="application/json",
                subject=f"SensorData-{message_data['sensorId']}"
            )
            sender.send_messages(message)
            print(f"✓ Sent sensor data: {message_data['sensorId']} - Temp: {message_data['readings']['temperature']}°C")
    
    print(f"\nSuccessfully sent {count} messages to topic '{TOPIC_NAME}'")


def send_batch_to_queue(client: ServiceBusClient, count: int = 10) -> None:
    """Send a batch of messages to the queue for better performance."""
    print(f"\n{'='*50}")
    print(f"Sending batch of {count} messages to Queue: {QUEUE_NAME}")
    print(f"{'='*50}")
    
    with client.get_queue_sender(queue_name=QUEUE_NAME) as sender:
        batch = sender.create_message_batch()
        
        for i in range(count):
            message_data = generate_dummy_queue_message()
            message = ServiceBusMessage(
                body=json.dumps(message_data),
                content_type="application/json"
            )
            try:
                batch.add_message(message)
            except ValueError:
                # Batch is full, send it and create a new one
                sender.send_messages(batch)
                batch = sender.create_message_batch()
                batch.add_message(message)
        
        # Send any remaining messages
        if len(batch) > 0:
            sender.send_messages(batch)
    
    print(f"✓ Successfully sent batch of {count} messages to queue '{QUEUE_NAME}'")


def main():
    """Main function to send messages to queue and topic."""
    print("\n" + "="*60)
    print("Azure Service Bus Message Sender")
    print("="*60)
    print(f"Namespace: {SERVICEBUS_FULLY_QUALIFIED_NAMESPACE}")
    print(f"Queue: {QUEUE_NAME}")
    print(f"Topic: {TOPIC_NAME}")
    print("="*60)
    
    try:
        # Create the Service Bus client
        client = get_servicebus_client()
        print("\n✓ Connected to Azure Service Bus using Azure CLI credentials")
        
        with client:
            # Send individual messages to queue
            send_messages_to_queue(client, count=3)
            
            # Send individual messages to topic
            send_messages_to_topic(client, count=3)
            
            # Send a batch to queue
            send_batch_to_queue(client, count=5)
        
        print("\n" + "="*60)
        print("All messages sent successfully!")
        print("="*60 + "\n")
        
    except Exception as e:
        print(f"\n❌ Error: {type(e).__name__}: {e}")
        raise


if __name__ == "__main__":
    main()

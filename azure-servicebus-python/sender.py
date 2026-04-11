"""
Azure Service Bus Message Sender

This module provides functionality to send messages to an Azure Service Bus Queue
using Azure CLI credentials for authentication.
"""

import json
from datetime import datetime
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.identity import AzureCliCredential

from config import (
    SERVICEBUS_FULLY_QUALIFIED_NAMESPACE,
    QUEUE_NAME,
    validate_config
)


def get_servicebus_client():
    """
    Create and return a Service Bus client using Azure CLI credentials.
    
    Returns:
        ServiceBusClient: Authenticated Service Bus client
    """
    # Use Azure CLI credential for authentication
    credential = AzureCliCredential()
    
    # Create the Service Bus client
    client = ServiceBusClient(
        fully_qualified_namespace=SERVICEBUS_FULLY_QUALIFIED_NAMESPACE,
        credential=credential
    )
    
    return client


def send_single_message(message_body: str | dict) -> None:
    """
    Send a single message to the Service Bus queue.
    
    Args:
        message_body: The message content (string or dict that will be JSON serialized)
    """
    validate_config()
    
    # Convert dict to JSON string if needed
    if isinstance(message_body, dict):
        message_body = json.dumps(message_body)
    
    with get_servicebus_client() as client:
        with client.get_queue_sender(queue_name=QUEUE_NAME) as sender:
            # Create and send the message
            message = ServiceBusMessage(message_body)
            sender.send_messages(message)
            print(f"✓ Sent message: {message_body[:100]}...")


def send_batch_messages(messages: list) -> None:
    """
    Send a batch of messages to the Service Bus queue.
    
    Args:
        messages: List of message bodies (strings or dicts)
    """
    validate_config()
    
    with get_servicebus_client() as client:
        with client.get_queue_sender(queue_name=QUEUE_NAME) as sender:
            # Create a batch
            batch = sender.create_message_batch()
            
            for msg in messages:
                # Convert dict to JSON string if needed
                if isinstance(msg, dict):
                    msg = json.dumps(msg)
                
                try:
                    # Try to add message to batch
                    batch.add_message(ServiceBusMessage(msg))
                except ValueError:
                    # Batch is full, send it and create a new one
                    sender.send_messages(batch)
                    print(f"✓ Sent batch of messages")
                    batch = sender.create_message_batch()
                    batch.add_message(ServiceBusMessage(msg))
            
            # Send any remaining messages
            if len(batch) > 0:
                sender.send_messages(batch)
                print(f"✓ Sent final batch of {len(batch)} message(s)")


def send_scheduled_message(message_body: str | dict, schedule_time: datetime) -> int:
    """
    Schedule a message to be sent at a specific time.
    
    Args:
        message_body: The message content
        schedule_time: When the message should become available
        
    Returns:
        int: The sequence number of the scheduled message
    """
    validate_config()
    
    if isinstance(message_body, dict):
        message_body = json.dumps(message_body)
    
    with get_servicebus_client() as client:
        with client.get_queue_sender(queue_name=QUEUE_NAME) as sender:
            message = ServiceBusMessage(message_body)
            sequence_number = sender.schedule_messages(message, schedule_time)
            print(f"✓ Scheduled message for {schedule_time}, sequence: {sequence_number[0]}")
            return sequence_number[0]


# Example usage
if __name__ == "__main__":
    # Example 1: Send a simple string message
    print("\n--- Sending a simple message ---")
    send_single_message("Hello from Azure Service Bus!")
    
    # Example 2: Send a JSON message
    print("\n--- Sending a JSON message ---")
    json_message = {
        "event_type": "order_created",
        "order_id": "ORD-12345",
        "customer": "John Doe",
        "amount": 99.99,
        "timestamp": datetime.utcnow().isoformat()
    }
    send_single_message(json_message)
    
    # Example 3: Send batch messages
    print("\n--- Sending batch messages ---")
    batch_messages = [
        {"id": 1, "message": "Batch message 1"},
        {"id": 2, "message": "Batch message 2"},
        {"id": 3, "message": "Batch message 3"},
    ]
    send_batch_messages(batch_messages)
    
    print("\n✓ All messages sent successfully!")

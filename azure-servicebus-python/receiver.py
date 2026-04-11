"""
Azure Service Bus Message Receiver

This module provides functionality to receive messages from an Azure Service Bus Queue
using Azure CLI credentials for authentication.
"""

import json
from azure.servicebus import ServiceBusClient, ServiceBusReceiveMode
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
    credential = AzureCliCredential()
    
    client = ServiceBusClient(
        fully_qualified_namespace=SERVICEBUS_FULLY_QUALIFIED_NAMESPACE,
        credential=credential
    )
    
    return client


def receive_messages(max_messages: int = 10, max_wait_time: int = 5) -> list:
    """
    Receive messages from the Service Bus queue using PEEK_LOCK mode.
    Messages are completed after processing.
    
    Args:
        max_messages: Maximum number of messages to receive
        max_wait_time: Maximum time to wait for messages (seconds)
        
    Returns:
        list: List of received message bodies
    """
    validate_config()
    received_messages = []
    
    with get_servicebus_client() as client:
        with client.get_queue_receiver(
            queue_name=QUEUE_NAME,
            receive_mode=ServiceBusReceiveMode.PEEK_LOCK,
            max_wait_time=max_wait_time
        ) as receiver:
            
            messages = receiver.receive_messages(
                max_message_count=max_messages,
                max_wait_time=max_wait_time
            )
            
            for message in messages:
                try:
                    # Get message body
                    body = str(message)
                    
                    # Try to parse as JSON
                    try:
                        body = json.loads(body)
                    except json.JSONDecodeError:
                        pass  # Keep as string if not JSON
                    
                    print(f"✓ Received message: {body}")
                    received_messages.append(body)
                    
                    # Complete the message (removes from queue)
                    receiver.complete_message(message)
                    
                except Exception as e:
                    print(f"✗ Error processing message: {e}")
                    # Abandon message to make it available again
                    receiver.abandon_message(message)
    
    return received_messages


def receive_and_process(
    process_func: callable,
    max_messages: int = 10,
    max_wait_time: int = 5
) -> int:
    """
    Receive messages and process them with a custom function.
    
    Args:
        process_func: Function to process each message (takes message body as argument)
        max_messages: Maximum number of messages to receive
        max_wait_time: Maximum time to wait for messages (seconds)
        
    Returns:
        int: Number of successfully processed messages
    """
    validate_config()
    processed_count = 0
    
    with get_servicebus_client() as client:
        with client.get_queue_receiver(
            queue_name=QUEUE_NAME,
            receive_mode=ServiceBusReceiveMode.PEEK_LOCK,
            max_wait_time=max_wait_time
        ) as receiver:
            
            messages = receiver.receive_messages(
                max_message_count=max_messages,
                max_wait_time=max_wait_time
            )
            
            for message in messages:
                try:
                    body = str(message)
                    
                    # Try to parse as JSON
                    try:
                        body = json.loads(body)
                    except json.JSONDecodeError:
                        pass
                    
                    # Process the message
                    process_func(body)
                    
                    # Complete the message
                    receiver.complete_message(message)
                    processed_count += 1
                    
                except Exception as e:
                    print(f"✗ Error processing message: {e}")
                    receiver.abandon_message(message)
    
    return processed_count


def receive_messages_continuous(
    process_func: callable = None,
    max_wait_time: int = 30
) -> None:
    """
    Continuously receive and process messages from the queue.
    Press Ctrl+C to stop.
    
    Args:
        process_func: Optional function to process each message
        max_wait_time: Maximum time to wait for messages in each iteration
    """
    validate_config()
    print(f"Starting continuous receiver for queue: {QUEUE_NAME}")
    print("Press Ctrl+C to stop...\n")
    
    try:
        with get_servicebus_client() as client:
            with client.get_queue_receiver(
                queue_name=QUEUE_NAME,
                receive_mode=ServiceBusReceiveMode.PEEK_LOCK,
                max_wait_time=max_wait_time
            ) as receiver:
                
                while True:
                    messages = receiver.receive_messages(
                        max_message_count=10,
                        max_wait_time=max_wait_time
                    )
                    
                    if not messages:
                        print("No messages received, waiting...")
                        continue
                    
                    for message in messages:
                        try:
                            body = str(message)
                            
                            try:
                                body = json.loads(body)
                            except json.JSONDecodeError:
                                pass
                            
                            if process_func:
                                process_func(body)
                            else:
                                print(f"✓ Received: {body}")
                            
                            receiver.complete_message(message)
                            
                        except Exception as e:
                            print(f"✗ Error: {e}")
                            receiver.abandon_message(message)
                            
    except KeyboardInterrupt:
        print("\n\nReceiver stopped by user.")


def peek_messages(max_messages: int = 10) -> list:
    """
    Peek at messages in the queue without removing them.
    
    Args:
        max_messages: Maximum number of messages to peek
        
    Returns:
        list: List of peeked message bodies
    """
    validate_config()
    peeked_messages = []
    
    with get_servicebus_client() as client:
        with client.get_queue_receiver(queue_name=QUEUE_NAME) as receiver:
            messages = receiver.peek_messages(max_message_count=max_messages)
            
            for message in messages:
                body = str(message)
                
                try:
                    body = json.loads(body)
                except json.JSONDecodeError:
                    pass
                
                print(f"👁 Peeked message: {body}")
                peeked_messages.append(body)
    
    return peeked_messages


# Example usage
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Azure Service Bus Receiver")
    parser.add_argument(
        "--mode",
        choices=["receive", "continuous", "peek"],
        default="receive",
        help="Receive mode: receive (default), continuous, or peek"
    )
    parser.add_argument(
        "--max-messages",
        type=int,
        default=10,
        help="Maximum number of messages to receive"
    )
    
    args = parser.parse_args()
    
    if args.mode == "receive":
        print(f"\n--- Receiving up to {args.max_messages} messages ---")
        messages = receive_messages(max_messages=args.max_messages)
        print(f"\nTotal received: {len(messages)} message(s)")
        
    elif args.mode == "continuous":
        print("\n--- Starting continuous receiver ---")
        receive_messages_continuous()
        
    elif args.mode == "peek":
        print(f"\n--- Peeking at up to {args.max_messages} messages ---")
        messages = peek_messages(max_messages=args.max_messages)
        print(f"\nTotal peeked: {len(messages)} message(s)")

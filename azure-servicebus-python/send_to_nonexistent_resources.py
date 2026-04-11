"""
Azure Service Bus Error Handling Demo

This program intentionally tries to send messages to non-existent
queues and topics to demonstrate error handling.

Service Bus: svcdemoprmgeorepl
Resource Group: apim-vinay-rg

Non-existent resources (for testing):
- Queue: nonexistent_queue_xyz
- Topic: nonexistent_topic_abc
"""

import json
from datetime import datetime
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.servicebus.exceptions import (
    ServiceBusError,
    ServiceBusConnectionError,
    MessagingEntityNotFoundError,
    ServiceBusAuthenticationError,
    ServiceBusAuthorizationError
)
from azure.identity import AzureCliCredential

# Configuration
SERVICEBUS_NAMESPACE = "svcdemoprmgeorepl"
SERVICEBUS_FULLY_QUALIFIED_NAMESPACE = f"{SERVICEBUS_NAMESPACE}.servicebus.windows.net"

# Non-existent resources for testing error handling
FAKE_QUEUE_NAME = "nonexistent_queue_xyz_12345"
FAKE_TOPIC_NAME = "nonexistent_topic_abc_67890"


def get_servicebus_client() -> ServiceBusClient:
    """Create and return a Service Bus client using Azure CLI credentials."""
    credential = AzureCliCredential()
    return ServiceBusClient(
        fully_qualified_namespace=SERVICEBUS_FULLY_QUALIFIED_NAMESPACE,
        credential=credential
    )


def generate_test_message() -> dict:
    """Generate a simple test message."""
    return {
        "messageId": "test-msg-001",
        "timestamp": datetime.utcnow().isoformat(),
        "content": "This message will fail to send"
    }


def try_send_to_nonexistent_queue(client: ServiceBusClient, count: int = 500) -> dict:
    """
    Attempt to send messages to a queue that doesn't exist.
    This demonstrates how to handle MessagingEntityNotFoundError.
    
    Args:
        client: ServiceBusClient instance
        count: Number of error attempts to generate (default 500)
    
    Returns:
        dict with error statistics
    """
    print(f"\n{'='*60}")
    print(f"TEST 1: Sending {count} messages to non-existent queue: '{FAKE_QUEUE_NAME}'")
    print(f"{'='*60}")
    
    stats = {
        "total_attempts": count,
        "entity_not_found": 0,
        "authorization_errors": 0,
        "other_errors": 0
    }
    
    for i in range(count):
        try:
            with client.get_queue_sender(queue_name=FAKE_QUEUE_NAME) as sender:
                message_data = generate_test_message()
                message_data["attempt"] = i + 1
                message = ServiceBusMessage(
                    body=json.dumps(message_data),
                    content_type="application/json"
                )
                sender.send_messages(message)
                
        except MessagingEntityNotFoundError:
            stats["entity_not_found"] += 1
            if (i + 1) % 50 == 0 or i == 0:
                print(f"   ❌ Attempt {i+1}/{count}: MessagingEntityNotFoundError")
                
        except ServiceBusAuthorizationError:
            stats["authorization_errors"] += 1
            if (i + 1) % 50 == 0 or i == 0:
                print(f"   ❌ Attempt {i+1}/{count}: ServiceBusAuthorizationError")
                
        except ServiceBusError as e:
            stats["other_errors"] += 1
            if (i + 1) % 50 == 0 or i == 0:
                print(f"   ❌ Attempt {i+1}/{count}: {type(e).__name__}")
    
    print(f"\n   Queue Error Summary:")
    print(f"   - Total attempts: {stats['total_attempts']}")
    print(f"   - Entity not found errors: {stats['entity_not_found']}")
    print(f"   - Authorization errors: {stats['authorization_errors']}")
    print(f"   - Other errors: {stats['other_errors']}")
    
    return stats


def try_send_to_nonexistent_topic(client: ServiceBusClient, count: int = 500) -> dict:
    """
    Attempt to send messages to a topic that doesn't exist.
    This demonstrates how to handle MessagingEntityNotFoundError.
    
    Args:
        client: ServiceBusClient instance
        count: Number of error attempts to generate (default 500)
    
    Returns:
        dict with error statistics
    """
    print(f"\n{'='*60}")
    print(f"TEST 2: Sending {count} messages to non-existent topic: '{FAKE_TOPIC_NAME}'")
    print(f"{'='*60}")
    
    stats = {
        "total_attempts": count,
        "entity_not_found": 0,
        "authorization_errors": 0,
        "other_errors": 0
    }
    
    for i in range(count):
        try:
            with client.get_topic_sender(topic_name=FAKE_TOPIC_NAME) as sender:
                message_data = generate_test_message()
                message_data["attempt"] = i + 1
                message = ServiceBusMessage(
                    body=json.dumps(message_data),
                    content_type="application/json"
                )
                sender.send_messages(message)
                
        except MessagingEntityNotFoundError:
            stats["entity_not_found"] += 1
            if (i + 1) % 50 == 0 or i == 0:
                print(f"   ❌ Attempt {i+1}/{count}: MessagingEntityNotFoundError")
                
        except ServiceBusAuthorizationError:
            stats["authorization_errors"] += 1
            if (i + 1) % 50 == 0 or i == 0:
                print(f"   ❌ Attempt {i+1}/{count}: ServiceBusAuthorizationError")
                
        except ServiceBusError as e:
            stats["other_errors"] += 1
            if (i + 1) % 50 == 0 or i == 0:
                print(f"   ❌ Attempt {i+1}/{count}: {type(e).__name__}")
    
    print(f"\n   Topic Error Summary:")
    print(f"   - Total attempts: {stats['total_attempts']}")
    print(f"   - Entity not found errors: {stats['entity_not_found']}")
    print(f"   - Authorization errors: {stats['authorization_errors']}")
    print(f"   - Other errors: {stats['other_errors']}")
    
    return stats


def try_send_to_wrong_namespace() -> None:
    """
    Attempt to connect to a Service Bus namespace that doesn't exist.
    This demonstrates connection error handling.
    """
    print(f"\n{'='*60}")
    print("TEST 3: Connecting to non-existent namespace")
    print(f"{'='*60}")
    
    fake_namespace = "nonexistent-servicebus-namespace-xyz.servicebus.windows.net"
    
    try:
        credential = AzureCliCredential()
        client = ServiceBusClient(
            fully_qualified_namespace=fake_namespace,
            credential=credential
        )
        
        with client:
            with client.get_queue_sender(queue_name="any-queue") as sender:
                message = ServiceBusMessage(body="test")
                sender.send_messages(message)
                
    except ServiceBusConnectionError as e:
        print(f"❌ ServiceBusConnectionError caught!")
        print(f"   Namespace: {fake_namespace}")
        print(f"   Error: Could not establish connection")
        print(f"   Details: {e}")
        print("\n   Resolution: Verify the namespace name and network connectivity")
        
    except ServiceBusAuthenticationError as e:
        print(f"❌ ServiceBusAuthenticationError caught!")
        print(f"   Error: Authentication failed")
        print(f"   Details: {e}")
        
    except Exception as e:
        print(f"❌ {type(e).__name__} caught!")
        print(f"   Details: {e}")


def demonstrate_all_error_types():
    """Show common error scenarios and how to handle them."""
    print("\n" + "="*60)
    print("Common Azure Service Bus Errors and Handling")
    print("="*60)
    
    errors_info = [
        {
            "error": "MessagingEntityNotFoundError",
            "cause": "Queue, topic, or subscription doesn't exist",
            "resolution": "Verify entity name and create if missing"
        },
        {
            "error": "ServiceBusAuthenticationError",
            "cause": "Invalid or expired credentials",
            "resolution": "Run 'az login' to refresh Azure CLI credentials"
        },
        {
            "error": "ServiceBusAuthorizationError",
            "cause": "Insufficient permissions on the entity",
            "resolution": "Grant appropriate RBAC roles (e.g., Azure Service Bus Data Sender)"
        },
        {
            "error": "ServiceBusConnectionError",
            "cause": "Network issues or invalid namespace",
            "resolution": "Check network connectivity and namespace name"
        },
        {
            "error": "MessageSizeExceededError",
            "cause": "Message exceeds maximum size (256KB standard, 100MB premium)",
            "resolution": "Reduce message size or use claim check pattern"
        }
    ]
    
    for info in errors_info:
        print(f"\n• {info['error']}")
        print(f"  Cause: {info['cause']}")
        print(f"  Resolution: {info['resolution']}")


def main():
    """Main function to demonstrate error handling."""
    print("\n" + "="*60)
    print("Azure Service Bus - Error Handling Demo")
    print("="*60)
    print(f"Namespace: {SERVICEBUS_FULLY_QUALIFIED_NAMESPACE}")
    print(f"Fake Queue: {FAKE_QUEUE_NAME}")
    print(f"Fake Topic: {FAKE_TOPIC_NAME}")
    print("="*60)
    
    try:
        # Create the Service Bus client
        client = get_servicebus_client()
        print("\n✓ Connected to Azure Service Bus using Azure CLI credentials")
        
        with client:
            # Test 1: Try sending 500 messages to non-existent queue
            queue_stats = try_send_to_nonexistent_queue(client, count=500)
            
            # Test 2: Try sending 500 messages to non-existent topic
            topic_stats = try_send_to_nonexistent_topic(client, count=500)
        
        # Test 3: Try connecting to non-existent namespace
        try_send_to_wrong_namespace()
        
        # Show error handling reference
        demonstrate_all_error_types()
        
        # Final summary
        total_errors = (
            queue_stats["entity_not_found"] + queue_stats["authorization_errors"] + queue_stats["other_errors"] +
            topic_stats["entity_not_found"] + topic_stats["authorization_errors"] + topic_stats["other_errors"]
        )
        
        print("\n" + "="*60)
        print(f"TOTAL ERRORS GENERATED: {total_errors}")
        print(f"  - Queue errors: {queue_stats['total_attempts']}")
        print(f"  - Topic errors: {topic_stats['total_attempts']}")
        print("Error handling demo completed!")
        print("="*60 + "\n")
        
    except Exception as e:
        print(f"\n❌ Unexpected error: {type(e).__name__}: {e}")
        raise


if __name__ == "__main__":
    main()

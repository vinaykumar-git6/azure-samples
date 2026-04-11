"""
Azure Service Bus Demo Application

This is the main entry point demonstrating send and receive functionality
for Azure Service Bus using Azure CLI credentials.
"""

import argparse
import json
from datetime import datetime

from sender import send_single_message, send_batch_messages
from receiver import receive_messages, peek_messages, receive_messages_continuous


def demo_send():
    """Demonstrate sending messages to Service Bus."""
    print("=" * 50)
    print("SENDING MESSAGES TO AZURE SERVICE BUS")
    print("=" * 50)
    
    # Send a simple text message
    print("\n1. Sending a simple text message:")
    send_single_message("Hello, Azure Service Bus!")
    
    # Send a JSON message
    print("\n2. Sending a JSON message:")
    order_message = {
        "event_type": "order_created",
        "order_id": f"ORD-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "customer": {
            "name": "John Doe",
            "email": "john.doe@example.com"
        },
        "items": [
            {"product": "Widget A", "quantity": 2, "price": 29.99},
            {"product": "Widget B", "quantity": 1, "price": 49.99}
        ],
        "total": 109.97,
        "timestamp": datetime.utcnow().isoformat()
    }
    send_single_message(order_message)
    
    # Send batch messages
    print("\n3. Sending batch messages:")
    notifications = [
        {"type": "email", "to": "user1@example.com", "subject": "Welcome!"},
        {"type": "sms", "to": "+1234567890", "message": "Your code is 123456"},
        {"type": "push", "device_id": "device123", "title": "New Update"},
    ]
    send_batch_messages(notifications)
    
    print("\n✓ All demo messages sent!")


def demo_receive():
    """Demonstrate receiving messages from Service Bus."""
    print("=" * 50)
    print("RECEIVING MESSAGES FROM AZURE SERVICE BUS")
    print("=" * 50)
    
    print("\nReceiving messages...")
    messages = receive_messages(max_messages=10, max_wait_time=5)
    
    if messages:
        print(f"\n✓ Received {len(messages)} message(s)")
        for i, msg in enumerate(messages, 1):
            print(f"\nMessage {i}:")
            if isinstance(msg, dict):
                print(json.dumps(msg, indent=2))
            else:
                print(msg)
    else:
        print("\nNo messages in the queue.")


def demo_peek():
    """Demonstrate peeking at messages without removing them."""
    print("=" * 50)
    print("PEEKING AT MESSAGES IN AZURE SERVICE BUS")
    print("=" * 50)
    
    print("\nPeeking at messages (they will remain in the queue)...")
    messages = peek_messages(max_messages=10)
    
    if messages:
        print(f"\n✓ Found {len(messages)} message(s) in queue")
    else:
        print("\nNo messages in the queue.")


def main():
    parser = argparse.ArgumentParser(
        description="Azure Service Bus Demo - Send and Receive Messages",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python main.py send           # Send demo messages
  python main.py receive        # Receive messages from queue
  python main.py peek           # Peek at messages without removing
  python main.py continuous     # Start continuous receiver
  python main.py demo           # Run full send/receive demo
        """
    )
    
    parser.add_argument(
        "action",
        choices=["send", "receive", "peek", "continuous", "demo"],
        help="Action to perform"
    )
    
    parser.add_argument(
        "--message",
        "-m",
        type=str,
        help="Custom message to send (for 'send' action)"
    )
    
    parser.add_argument(
        "--max-messages",
        type=int,
        default=10,
        help="Maximum messages to receive (default: 10)"
    )
    
    args = parser.parse_args()
    
    try:
        if args.action == "send":
            if args.message:
                print(f"Sending custom message: {args.message}")
                send_single_message(args.message)
            else:
                demo_send()
                
        elif args.action == "receive":
            demo_receive()
            
        elif args.action == "peek":
            demo_peek()
            
        elif args.action == "continuous":
            print("Starting continuous message receiver...")
            print("Press Ctrl+C to stop.\n")
            receive_messages_continuous()
            
        elif args.action == "demo":
            # Run full demo
            demo_send()
            print("\n" + "=" * 50)
            print("Waiting a moment before receiving...")
            print("=" * 50)
            import time
            time.sleep(2)
            demo_receive()
            
    except ValueError as e:
        print(f"\n✗ Configuration Error: {e}")
        print("Please ensure you have set up your .env file correctly.")
        print("Copy .env.example to .env and fill in your values.")
        
    except Exception as e:
        print(f"\n✗ Error: {e}")
        raise


if __name__ == "__main__":
    main()

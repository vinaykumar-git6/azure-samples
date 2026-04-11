"""Configuration module for Azure Service Bus connection."""

import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Azure Service Bus Configuration
SERVICEBUS_NAMESPACE = os.getenv("SERVICEBUS_NAMESPACE")
QUEUE_NAME = os.getenv("QUEUE_NAME")

# Construct the fully qualified namespace
SERVICEBUS_FULLY_QUALIFIED_NAMESPACE = f"{SERVICEBUS_NAMESPACE}.servicebus.windows.net"


def validate_config():
    """Validate that all required configuration values are set."""
    missing = []
    if not SERVICEBUS_NAMESPACE:
        missing.append("SERVICEBUS_NAMESPACE")
    if not QUEUE_NAME:
        missing.append("QUEUE_NAME")
    
    if missing:
        raise ValueError(f"Missing required environment variables: {', '.join(missing)}")
    
    return True

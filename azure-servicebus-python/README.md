# Azure Service Bus Python Client

A Python project to send and receive messages from Azure Service Bus Queue using Azure CLI credentials for authentication.

## Features

- ✅ Send single messages to Service Bus Queue
- ✅ Send batch messages
- ✅ Schedule messages for future delivery
- ✅ Receive messages with PEEK_LOCK mode
- ✅ Continuous message receiver
- ✅ Peek at messages without removing them
- ✅ Azure CLI credential authentication (no connection strings needed)

## Prerequisites

1. **Python 3.9+** installed
2. **Azure CLI** installed and logged in
3. **Azure Service Bus namespace** with a queue created
4. **Appropriate RBAC permissions** on the Service Bus namespace

### Required Azure Permissions

Your Azure CLI user needs one of these roles on the Service Bus namespace:
- `Azure Service Bus Data Owner` - Full access
- `Azure Service Bus Data Sender` - Send messages only
- `Azure Service Bus Data Receiver` - Receive messages only

To assign the role using Azure CLI:

```powershell
# Get your user object ID
$userId = az ad signed-in-user show --query id -o tsv

# Assign the Data Owner role (for full access)
az role assignment create `
    --assignee $userId `
    --role "Azure Service Bus Data Owner" `
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ServiceBus/namespaces/<namespace>"
```

## Setup

### 1. Clone and Install Dependencies

```powershell
cd azure-servicebus-python
pip install -r requirements.txt
```

### 2. Configure Environment

Copy the example environment file and update with your values:

```powershell
copy .env.example .env
```

Edit `.env` with your Service Bus details:

```env
SERVICEBUS_NAMESPACE=your-servicebus-namespace
QUEUE_NAME=your-queue-name
```

> **Note**: Only provide the namespace name, not the full URL. The code automatically appends `.servicebus.windows.net`.

### 3. Login to Azure CLI

```powershell
az login
```

## Usage

### Run the Demo

```powershell
# Full demo (send and receive)
python main.py demo

# Send demo messages
python main.py send

# Send a custom message
python main.py send -m "My custom message"

# Receive messages
python main.py receive

# Peek at messages (without removing)
python main.py peek

# Start continuous receiver
python main.py continuous
```

### Use as a Module

```python
from sender import send_single_message, send_batch_messages
from receiver import receive_messages, receive_messages_continuous

# Send a simple message
send_single_message("Hello, Service Bus!")

# Send a JSON message
send_single_message({
    "event": "user_created",
    "user_id": "12345",
    "email": "user@example.com"
})

# Send multiple messages in a batch
send_batch_messages([
    {"id": 1, "data": "Message 1"},
    {"id": 2, "data": "Message 2"},
    {"id": 3, "data": "Message 3"},
])

# Receive messages
messages = receive_messages(max_messages=10)
for msg in messages:
    print(msg)

# Process messages with custom function
def my_processor(message):
    print(f"Processing: {message}")

from receiver import receive_and_process
receive_and_process(my_processor, max_messages=5)
```

## Project Structure

```
azure-servicebus-python/
├── config.py           # Configuration and environment loading
├── sender.py           # Message sending functionality
├── receiver.py         # Message receiving functionality
├── main.py             # Main CLI application
├── requirements.txt    # Python dependencies
├── .env.example        # Example environment configuration
└── README.md           # This file
```

## Azure CLI Commands Reference

### Create Service Bus Namespace and Queue

```powershell
# Set variables
$resourceGroup = "my-resource-group"
$location = "eastus"
$namespace = "my-servicebus-ns"
$queueName = "my-queue"

# Create resource group
az group create --name $resourceGroup --location $location

# Create Service Bus namespace
az servicebus namespace create `
    --name $namespace `
    --resource-group $resourceGroup `
    --location $location `
    --sku Standard

# Create queue
az servicebus queue create `
    --name $queueName `
    --namespace-name $namespace `
    --resource-group $resourceGroup

# Assign RBAC role to current user
$userId = az ad signed-in-user show --query id -o tsv
az role assignment create `
    --assignee $userId `
    --role "Azure Service Bus Data Owner" `
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$resourceGroup/providers/Microsoft.ServiceBus/namespaces/$namespace"
```

## Troubleshooting

### Authentication Errors

1. Make sure you're logged in to Azure CLI:
   ```powershell
   az login
   ```

2. Verify you have the correct subscription:
   ```powershell
   az account show
   az account set --subscription "Your Subscription Name"
   ```

3. Check RBAC permissions:
   ```powershell
   az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --all
   ```

### No Messages Received

- Verify the queue name is correct
- Check if there are messages in the queue using Azure Portal
- Ensure you have `Azure Service Bus Data Receiver` or `Azure Service Bus Data Owner` role

## License

MIT License

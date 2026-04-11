# Azure Event Hubs Kafka Producer

Simple Python application to send messages to Azure Event Hubs using Kafka protocol with Azure AD authentication.

## 📋 Prerequisites

- Python 3.8+
- Azure Event Hubs namespace (Standard or Premium tier)
- Event Hub created in the namespace
- Azure AD authentication (Azure CLI or Service Principal)
- **Azure Event Hubs Data Sender** role assigned

## 🚀 Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Configure Environment

```bash
# Copy the template
cp .env.template .env

# Edit .env with your Event Hub details
```

### 3. Set Up Azure AD Authentication

**Option A: Azure CLI (Recommended for Development)**
```bash
az login
```

**Option B: Service Principal**
```bash
# Create service principal
az ad sp create-for-rbac --name kafka-sender-sp

# Set credentials in .env:
# AZURE_CLIENT_ID=<appId>
# AZURE_TENANT_ID=<tenant>
# AZURE_CLIENT_SECRET=<password>
```

### 4. Assign Permissions

```bash
# Get principal ID
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign "Azure Event Hubs Data Sender" role
az role assignment create \
  --role "Azure Event Hubs Data Sender" \
  --assignee $PRINCIPAL_ID \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.EventHub/namespaces/<namespace-name>
```

### 5. Run the Sender

```bash
python kafka_sender.py
```

### 6. Run the Receiver

```bash
python kafka_receiver.py
```

## 📤 What the Sender Does

1. Obtains Azure AD access token
2. Connects to Event Hubs
3. Sends 5 test messages with sensor data
4. Shows partition and offset for each message

## 📥 What the Receiver Does

1. Obtains Azure AD access token
2. Connects to Event Hubs consumer group
3. Receives messages from all partitions
4. Displays message details (partition, offset, body)
5. Updates checkpoint after each message
6. Stops after receiving 10 messages (configurable)

## 📊 Sample Output

```
============================================================
Azure Event Hubs Kafka Producer (Azure AD Auth)
============================================================
Namespace: MyEventHubNamespace0603.servicebus.windows.net
Event Hub: MyMQTTEventHub0603
Client ID: 86339c66-ee25-474d-b5bb-b334aad19c32

🔑 Getting Azure AD access token...
🔑 Using DefaultAzureCredential (az login, managed identity, etc.)
✅ Access token obtained (expires: 2025-11-17 18:05:46)

🔌 Connecting to Kafka broker: MyEventHubNamespace0603.servicebus.windows.net:9093
✅ Connected to Event Hubs Kafka broker

📤 Sending 5 test messages to topic: MyMQTTEventHub0603

📨 Sending message 1/5...
   Payload: {"message_id": 1, "timestamp": "2025-11-17T...", ...}
   ✅ Sent to partition 2 at offset 1234

...

============================================================
✅ Successfully sent 5 messages to Event Hub!
============================================================
```

## 🔧 Configuration

**Sender - Change number of messages:**
```python
# Edit kafka_sender.py
send_messages(num_messages=10)  # Send 10 messages
```

**Receiver - Change max messages to receive:**
```python
# Edit kafka_receiver.py
max_messages = 20  # Receive 20 messages then stop
```

**Receiver - Start from latest messages only:**
```python
# Edit kafka_receiver.py, in receive_messages()
starting_position="@latest"  # Instead of "-1"
```

## 📚 References

- [Azure Event Hubs for Apache Kafka](https://learn.microsoft.com/azure/event-hubs/event-hubs-for-kafka-ecosystem-overview)
- [Azure Event Hubs Azure AD Authentication](https://learn.microsoft.com/azure/event-hubs/authenticate-application)
- [kafka-python Documentation](https://kafka-python.readthedocs.io/)

## 📄 License

Sample project for Azure Event Hubs Kafka integration.

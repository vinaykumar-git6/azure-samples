# Azure Event Hubs MQTT Sender

Simple Python application to send test messages to Azure Event Hubs using the MQTT protocol with Azure AD authentication.

## 📋 Prerequisites

- Python 3.8+
- Azure Event Hubs namespace with MQTT enabled
- Event Hub created in the namespace
- Azure AD authentication (Azure CLI, Service Principal, or Managed Identity)
- **Azure Event Hubs Data Sender** role assigned to your identity

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

Required configuration in `.env`:

```env
EVENTHUB_NAMESPACE=MyEventHubNamespace0603.servicebus.windows.net
EVENTHUB_NAME=MyMQTTEventHub0603
AZURE_CLIENT_ID=321ff080-8e3c-4b1c-a9e5-22704c76ee0d
AZURE_TENANT_ID=your-tenant-id-here  # Optional for DefaultAzureCredential
AZURE_CLIENT_SECRET=                 # Optional - leave empty for az login
MQTT_PORT=8883
```

### 3. Set Up Azure AD Authentication

**Option A: Azure CLI (Recommended for Development)**
```bash
# Login with your Azure account
az login

# Verify your account
az account show
```

**Option B: Service Principal (Recommended for Production)**
```bash
# Create a service principal
az ad sp create-for-rbac --name mqtt-sender-sp

# Copy the output and set in .env:
# AZURE_CLIENT_ID=<appId>
# AZURE_TENANT_ID=<tenant>
# AZURE_CLIENT_SECRET=<password>
```

**Option C: Managed Identity**
When running on Azure (VM, AKS, App Service), the app automatically uses the managed identity. No additional configuration needed.

### 4. Assign Event Hubs Permissions

The identity needs "Azure Event Hubs Data Sender" role:

```bash
# For your user account
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

# Or for service principal
PRINCIPAL_ID=$(az ad sp show --id <client-id> --query id -o tsv)

# Assign the role
az role assignment create \
  --role "Azure Event Hubs Data Sender" \
  --assignee $PRINCIPAL_ID \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.EventHub/namespaces/<namespace-name>

# Wait 1-2 minutes for role to propagate
```

### 5. Run the Sender

```bash
python mqtt_sender.py
```

## 📤 What It Does

The script:
1. Obtains an Azure AD access token using Azure Identity SDK
2. Connects to Event Hubs using MQTT over TLS (port 8883) with token authentication
3. Sends 5 test messages with sensor data (temperature, humidity, status)
4. Displays connection and publish status
5. Disconnects gracefully

## 📊 Sample Output

```
============================================================
Azure Event Hubs MQTT Sender (Azure AD Auth)
============================================================
Namespace: MyEventHubNamespace0603.servicebus.windows.net
Event Hub: MyMQTTEventHub0603
Client ID: 321ff080-8e3c-4b1c-a9e5-22704c76ee0d
Port: 8883

🔑 Getting Azure AD access token...
🔑 Using DefaultAzureCredential (az login, managed identity, etc.)
✅ Access token obtained (expires: 2025-11-17 12:30:00)

🔌 Connecting to MyEventHubNamespace0603.servicebus.windows.net:8883...
✅ Connected to Azure Event Hubs MQTT broker
📤 Sending 5 test messages...

📨 Sending message 1/5...
   Topic: devices/events
   Payload: {"message_id": 1, "timestamp": "2025-11-17T10:30:00", ...}
   ✅ Message queued successfully
✅ Message published (message ID: 1)

...

============================================================
✅ Successfully sent 5 messages to Event Hub!
============================================================
```

## 📝 Message Format

Each message contains:

```json
{
  "message_id": 1,
  "timestamp": "2025-11-17T10:30:00.123456",
  "sensor_id": "sensor-1",
  "temperature": 20.5,
  "humidity": 52,
  "status": "active"
}
```

## 🔧 Customization

### Send More Messages

Edit the script to change the number of messages:

```python
send_test_messages(num_messages=10)  # Send 10 messages
```

### Custom Message Payload

Modify the `message` dictionary in `mqtt_sender.py`:

```python
message = {
    "your_field": "your_value",
    "custom_data": 123
}
```

## 🐛 Troubleshooting

### Authentication Errors
```bash
# Test Azure CLI login
az account show

# Test getting Event Hubs token manually
az account get-access-token --resource https://eventhubs.azure.net

# For service principal
az login --service-principal -u <client-id> -p <client-secret> --tenant <tenant-id>
```

### Connection Failed (Code 5 - Authorization Failed)
- Verify "Azure Event Hubs Data Sender" role is assigned
- Wait 1-2 minutes for role assignments to propagate
- Check role assignment: `az role assignment list --assignee <principal-id>`
- Ensure AZURE_CLIENT_ID matches your identity

### Connection Failed (Code 4)
- Verify namespace name is correct
- Check that MQTT is enabled on Event Hub namespace
- Ensure the Event Hub name exists

### SSL/TLS Errors
- Make sure port 8883 is accessible
- Check firewall settings
- Verify the namespace FQDN is correct

### Token Expiry
- Azure AD tokens expire after ~1 hour
- The script gets a fresh token on each run
- For long-running apps, implement token refresh logic

### Message Not Publishing
- Check Event Hub exists and is active
- Verify you have send permissions via Azure Monitor logs
- Check Event Hub quota limits

## 📚 References

- [Azure Event Hubs MQTT Support](https://learn.microsoft.com/azure/event-hubs/mqtt-support)
- [Azure Event Hubs Azure AD Authentication](https://learn.microsoft.com/azure/event-hubs/authenticate-application)
- [Azure Identity Python SDK](https://learn.microsoft.com/python/api/overview/azure/identity-readme)
- [Paho MQTT Python Client](https://www.eclipse.org/paho/index.php?page=clients/python/index.php)
- [Azure Event Hubs RBAC Roles](https://learn.microsoft.com/azure/event-hubs/authorize-access-azure-active-directory)

## 📄 License

This is a test/sample project for Azure Event Hubs MQTT integration.

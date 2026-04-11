# Azure Event Grid MQTT - JWT Authentication

Python MQTT client for Azure Event Grid using JWT (Azure AD) authentication.

## Features

- ✅ **JWT Authentication**: Uses Azure AD tokens instead of certificates
- ✅ **MQTT v5**: Leverages MQTT v5 protocol with OAUTH2-JWT
- ✅ **Azure Identity**: Supports Service Principal and DefaultAzureCredential
- ✅ **Auto Token Management**: Azure Identity SDK handles token refresh
- ✅ **Simple Configuration**: All settings via `.env` file

## Prerequisites

- Python 3.11+
- Azure CLI (for setup)
- Azure Event Grid namespace (already created: `myeventgrid-mqtt-ns0603`)
- Azure AD tenant access

## Quick Start

### 1. Run Azure Setup Script

```powershell
.\azure-setup-jwt.ps1
```

This will:
- Create topic space `sensors` with pattern `sensors/#`
- Create permission bindings (Publisher + Subscriber)
- Create Azure AD app registration
- Generate service principal and client secret
- Assign RBAC roles
- Register MQTT client
- Update `.env` file with credentials

### 2. Install Dependencies

```powershell
uv pip install -r requirements.txt
```

### 3. Run the MQTT Sender

```powershell
uv run python mqtt_sender.py
```

## Configuration

The `.env` file contains all configuration:

```bash
# Event Grid MQTT endpoint
EVENTGRID_HOSTNAME=myeventgrid-mqtt-ns0603.uaenorth-1.ts.eventgrid.azure.net

# MQTT topic to publish to
MQTT_TOPIC=sensors/telemetry

# MQTT port (always 8883 for TLS)
MQTT_PORT=8883

# MQTT Client ID (must be registered in Event Grid)
MQTT_CLIENT_ID=sensor-app-001

# Azure AD credentials (from app registration)
AZURE_CLIENT_ID=<your-client-id>
AZURE_TENANT_ID=<your-tenant-id>
AZURE_CLIENT_SECRET=<your-client-secret>
```

## Manual Setup

If you prefer manual setup, see [AZURE_CLI_COMMANDS.md](AZURE_CLI_COMMANDS.md) for detailed step-by-step Azure CLI commands.

## How It Works

### Authentication Flow

1. **Get JWT Token**
   - App requests token from Azure AD
   - Scope: `https://eventgrid.azure.net/.default`
   - Token valid for 1 hour

2. **Connect to Event Grid**
   - Protocol: MQTT v5 over TLS (port 8883)
   - Authentication Method: `OAUTH2-JWT`
   - Token passed in connection properties

3. **Publish/Subscribe**
   - RBAC roles validate permissions
   - Messages published to configured topic
   - Real-time message delivery

### Code Structure

```python
# Get Azure AD token
credential = ClientSecretCredential(...)
token = credential.get_token("https://eventgrid.azure.net/.default")

# Connect with MQTT v5
client = mqtt.Client(protocol=mqtt.MQTTv5)
properties = Properties(PacketTypes.CONNECT)
properties.AuthenticationMethod = "OAUTH2-JWT"
properties.AuthenticationData = token.token.encode('utf-8')

client.connect(hostname, 8883, properties=properties)
```

## Architecture

```
┌─────────────────────┐
│   Azure AD          │
│  (Entra ID)         │
└──────────┬──────────┘
           │ JWT Token
           ↓
┌─────────────────────┐
│  mqtt_sender.py     │
│  (Your App)         │
└──────────┬──────────┘
           │ MQTT v5 + OAUTH2-JWT
           ↓
┌─────────────────────┐
│ Event Grid          │
│ Namespace           │
│                     │
│ • Topic Space       │
│   └─ sensors/#      │
│                     │
│ • Permissions       │
│   ├─ Publisher      │
│   └─ Subscriber     │
│                     │
│ • Client            │
│   └─ sensor-app-001 │
└─────────────────────┘
```

## Differences from Certificate Auth

| Feature | Certificate Auth | JWT Auth |
|---------|-----------------|----------|
| **Authentication** | X.509 certificates | Azure AD tokens |
| **Setup** | Generate certificates | Create service principal |
| **Credential** | PEM files | Client secret |
| **Token Lifetime** | Certificate validity | 1 hour (auto-refresh) |
| **Best For** | IoT devices | Azure services/apps |
| **MQTT Version** | v3.1.1 | v5 |

## Troubleshooting

### Error: "Connection refused - not authorized" (code 5)

**Causes**:
- RBAC roles not assigned
- Token expired or invalid
- Client not registered

**Solutions**:
```powershell
# Check RBAC assignments
az role assignment list --scope $RESOURCE_ID --all

# Re-register client
az eventgrid namespace client create ...

# Verify token
az account get-access-token --resource https://eventgrid.azure.net
```

### Error: "Failed to get Azure AD token"

**Causes**:
- Invalid credentials in `.env`
- Service principal doesn't exist
- `az login` not performed (for DefaultAzureCredential)

**Solutions**:
```powershell
# Verify credentials
az ad sp show --id $AZURE_CLIENT_ID

# Login for DefaultAzureCredential
az login

# Re-generate secret
az ad app credential reset --id $AZURE_CLIENT_ID --append
```

### Error: "Client not found"

**Cause**: MQTT client not registered in Event Grid

**Solution**:
```powershell
az eventgrid namespace client create `
  --namespace-name myeventgrid-mqtt-ns0603 `
  --resource-group MyEventHubRG `
  --name sensor-app-001 `
  --state Enabled
```

## Testing

Run the sender:
```powershell
uv run python mqtt_sender.py
```

Expected output:
```
============================================================
Azure Event Grid MQTT Sender (JWT Auth)
============================================================
Event Grid Host: myeventgrid-mqtt-ns0603.uaenorth-1.ts.eventgrid.azure.net
MQTT Topic: sensors/telemetry
MQTT Client ID: sensor-app-001
Port: 8883

🔑 Getting Azure AD access token...
🔑 Using ClientSecretCredential (Service Principal)
✅ Access token obtained (expires: 2025-11-18 23:45:00)

🔒 Configuring TLS/SSL...
✅ TLS configured
🔌 Connecting to myeventgrid-mqtt-ns0603.uaenorth-1.ts.eventgrid.azure.net:8883...
   MQTT Client ID: sensor-app-001
   Authentication: OAUTH2-JWT
⏳ Waiting for connection...
✅ Connected to Azure Event Grid MQTT broker
✅ Connection established
📤 Sending 5 test messages...

📨 Sending message 1/5...
   Topic: sensors/telemetry
   Payload: {"message_id": 1, "timestamp": "2025-11-18T18:30:00", ...}
   ✅ Message queued successfully
...
```

## Files

- `mqtt_sender.py` - Main MQTT client with JWT auth
- `.env` - Configuration file
- `requirements.txt` - Python dependencies
- `azure-setup-jwt.ps1` - Automated Azure setup script
- `AZURE_CLI_COMMANDS.md` - Manual setup commands reference

## Resources

- [Azure Event Grid MQTT Documentation](https://learn.microsoft.com/azure/event-grid/mqtt-overview)
- [JWT Authentication Guide](https://learn.microsoft.com/azure/event-grid/mqtt-client-microsoft-entra-token-and-rbac)
- [Azure Identity SDK](https://learn.microsoft.com/python/api/overview/azure/identity-readme)
- [Paho MQTT Client](https://github.com/eclipse/paho.mqtt.python)

## Next Steps

1. ✅ Setup complete - Run the sender
2. 📝 Create MQTT subscriber (receiver)
3. 🔄 Implement message processing logic
4. 📊 Add monitoring and logging
5. 🚀 Deploy to Azure (App Service, Container Apps, etc.)

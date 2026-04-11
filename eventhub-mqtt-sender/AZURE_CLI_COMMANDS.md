# Azure CLI Commands for JWT Authentication Setup

## Variables Setup
```powershell
$SUBSCRIPTION_ID = "86339c66-ee25-474d-b5bb-b334aad19c32"
$RESOURCE_GROUP = "MyEventHubRG"
$EVENTGRID_NAMESPACE = "myeventgrid-mqtt-ns0603"
$RESOURCE_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/namespaces/$EVENTGRID_NAMESPACE"
```

---

## 1. Create Topic Space
**What it does**: Defines which MQTT topic patterns clients can access

```powershell
az resource create --id "$RESOURCE_ID/topicSpaces/sensors" --properties '{
    "topicTemplates": ["sensors/#"]
}'
```

**Explanation**:
- `topicSpaces/sensors`: Name of the topic space
- `sensors/#`: Pattern allowing topics like `sensors/telemetry`, `sensors/data`, etc.
- `#` is a wildcard matching any subtopic

---

## 2. Create Permission Bindings
**What it does**: Grants publish/subscribe rights to clients

### Publisher Permission
```powershell
az eventgrid namespace permission-binding create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-publisher-binding `
  --client-group-name '$all' `
  --topic-space-name sensors `
  --permission Publisher
```

### Subscriber Permission
```powershell
az eventgrid namespace permission-binding create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-subscriber-binding `
  --client-group-name '$all' `
  --topic-space-name sensors `
  --permission Subscriber
```

**Explanation**:
- `--client-group-name '$all'`: Built-in group including all registered clients
- `--permission Publisher/Subscriber`: Type of access granted

---

## 3. Create Azure AD App Registration
**What it does**: Creates a service principal for JWT token generation

```powershell
# Create app registration
$clientId = az ad app create --display-name "EventGridMQTTApp" --query appId -o tsv

# Create service principal
$spId = az ad sp create --id $clientId --query id -o tsv

# Generate client secret (SAVE THE OUTPUT!)
az ad app credential reset --id $clientId --append
```

**Explanation**:
- App Registration: Identity for your application in Azure AD
- Service Principal: Enterprise application object
- Client Secret: Password for authentication

**⚠️ Important**: Save the output containing:
- `appId` (Client ID)
- `tenant` (Tenant ID)
- `password` (Client Secret)

---

## 4. Assign RBAC Roles
**What it does**: Grants the service principal permission to use Event Grid MQTT

### Publisher Role
```powershell
az role assignment create `
  --assignee $spId `
  --role "EventGrid TopicSpaces Publisher" `
  --scope $RESOURCE_ID
```

### Subscriber Role
```powershell
az role assignment create `
  --assignee $spId `
  --role "EventGrid TopicSpaces Subscriber" `
  --scope $RESOURCE_ID
```

**Explanation**:
- `--assignee`: Service principal ID receiving permissions
- `--role`: Built-in Azure role for Event Grid MQTT
- `--scope`: Limits permissions to specific Event Grid namespace

---

## 5. Register MQTT Client
**What it does**: Registers the MQTT client in Event Grid namespace

```powershell
az eventgrid namespace client create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensor-app-001 `
  --state Enabled `
  --description "MQTT client for sensor data"
```

**Explanation**:
- `--name sensor-app-001`: MQTT Client ID (must match in your code)
- `--state Enabled`: Allows client to connect
- No authentication or attributes needed when using `$all` client group

---

## 6. Get Event Grid Hostname
**What it does**: Retrieves the MQTT broker endpoint

```powershell
$hostname = az resource show `
  --ids $RESOURCE_ID `
  --query "properties.topicSpacesConfiguration.hostname" `
  -o tsv

Write-Host "MQTT Hostname: $hostname"
```

---

## Optional: List Resources

### List Topic Spaces
```powershell
az resource list `
  --resource-group $RESOURCE_GROUP `
  --resource-type "Microsoft.EventGrid/namespaces/topicSpaces" `
  -o table
```

### List Permission Bindings
```powershell
az eventgrid namespace permission-binding list `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  -o table
```

### List Registered Clients
```powershell
az eventgrid namespace client list `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  -o table
```

### List Role Assignments
```powershell
az role assignment list `
  --scope $RESOURCE_ID `
  --query "[].{Principal:principalName, Role:roleDefinitionName}" `
  -o table
```

---

## Quick Setup (All in One)

Run the automated script:
```powershell
.\azure-setup-jwt.ps1
```

Or manually execute all commands above in sequence.

---

## Architecture Overview

```
Azure AD (Entra ID)
  ↓ (generates JWT token)
Your App (mqtt_sender.py)
  ↓ (MQTT v5 with OAUTH2-JWT)
Event Grid Namespace
  ├── Topic Space: sensors (sensors/#)
  ├── Permission Bindings
  │   ├── Publisher → $all → sensors
  │   └── Subscriber → $all → sensors
  └── Client: sensor-app-001
```

---

## How JWT Authentication Works

1. **App requests token from Azure AD**
   - Uses Client ID, Tenant ID, Client Secret
   - Scope: `https://eventgrid.azure.net/.default`

2. **Azure AD returns JWT token**
   - Token valid for 1 hour
   - Contains claims about the service principal

3. **App connects to Event Grid MQTT**
   - Protocol: MQTT v5
   - Authentication Method: `OAUTH2-JWT`
   - Authentication Data: JWT token

4. **Event Grid validates token**
   - Verifies signature with Azure AD
   - Checks RBAC role assignments
   - Validates client registration

5. **Connection established**
   - App can publish to `sensors/telemetry`
   - App can subscribe to `sensors/#`

---

## Troubleshooting Commands

### Check if topic space exists
```powershell
az resource show --id "$RESOURCE_ID/topicSpaces/sensors"
```

### Check client registration
```powershell
az eventgrid namespace client show `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensor-app-001
```

### Check RBAC assignments
```powershell
az role assignment list --scope $RESOURCE_ID --all
```

### Get Event Grid configuration
```powershell
az resource show --ids $RESOURCE_ID
```

---

## Cleanup Commands

### Delete client
```powershell
az eventgrid namespace client delete `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensor-app-001 `
  --yes
```

### Delete permission bindings
```powershell
az eventgrid namespace permission-binding delete `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-publisher-binding `
  --yes

az eventgrid namespace permission-binding delete `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-subscriber-binding `
  --yes
```

### Delete topic space
```powershell
az resource delete --id "$RESOURCE_ID/topicSpaces/sensors"
```

### Remove RBAC role assignments
```powershell
az role assignment delete `
  --assignee $spId `
  --role "EventGrid TopicSpaces Publisher" `
  --scope $RESOURCE_ID

az role assignment delete `
  --assignee $spId `
  --role "EventGrid TopicSpaces Subscriber" `
  --scope $RESOURCE_ID
```

### Delete service principal and app
```powershell
az ad sp delete --id $spId
az ad app delete --id $clientId
```

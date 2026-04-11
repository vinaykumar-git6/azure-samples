# Azure Event Hub Performance Test

Python project to test Azure Event Hub performance by publishing 1000+ events and measuring latency.

## Features

- **Publisher**: Sends multiple events to Azure Event Hub with timestamps
- **Subscriber**: Receives events and calculates latency
- **Excel Logging**: Logs all timestamps and metrics to Excel files
- **Performance Metrics**: Calculates average, min, and max latency

## Project Structure

```
eventhub-performance-test/
├── publisher.py          # Publishes events to Event Hub
├── subscriber.py         # Subscribes and receives events
├── run_test.py          # Runs both publisher and subscriber
├── requirements.txt     # Python dependencies
├── .env.example        # Environment variables template
└── README.md           # This file
```

## Prerequisites

1. **Azure Event Hub**:
   - Create an Event Hub namespace
   - Create an Event Hub (topic)
   - Your Azure account must have "Azure Event Hubs Data Owner" or "Azure Event Hubs Data Sender/Receiver" role

2. **Azure CLI Authentication**:
   - Install Azure CLI
   - Login: `az login`
   - Your CLI credentials will be used for authentication

3. **Python 3.8+**

## Setup

1. **Activate workspace virtual environment**:
```powershell
# From workspace root
.\.venv\Scripts\Activate.ps1
```

2. **Install dependencies** (if not already installed):
```powershell
uv pip install azure-eventhub azure-identity openpyxl python-dotenv
```

3. **Login to Azure**:
```powershell
az login
```

4. **Configure environment variables**:
   - Copy `.env.example` to `.env`
   - Update with your Event Hub details:

```env
EVENTHUB_NAMESPACE=your-namespace.servicebus.windows.net
EVENTHUB_NAME=your-eventhub-name
NUM_EVENTS=1000
```

## Usage

### Option 1: Run Complete Test (Recommended)
Runs publisher and subscriber sequentially:

```powershell
python run_test.py
```

### Option 2: Run Separately

**Publish events:**
```powershell
python publisher.py
```

**Subscribe to events (in another terminal):**
```powershell
python subscriber.py
```

## Output Files

The scripts generate Excel files with timestamps:

1. **`published_events_YYYYMMDD_HHMMSS.xlsx`**:
   - Event Number
   - Event ID
   - Published Timestamp
   - Published ISO format

2. **`received_events_YYYYMMDD_HHMMSS.xlsx`**:
   - Event Number
   - Event ID
   - Published Timestamp
   - Received Timestamp
   - Latency (ms)
   - Partition ID
   - Sequence Number
   - Enqueued Time
   - Statistics sheet with avg/min/max latency

## Sample Output

```
================================================================================
Event Hub Performance Test
================================================================================

STEP 1: Publishing events...
--------------------------------------------------------------------------------
Starting to publish 1000 events to Event Hub: my-eventhub
--------------------------------------------------------------------------------
Prepared 100 events...
Prepared 200 events...
...
Sent final batch of events...
--------------------------------------------------------------------------------
✓ Successfully published 1000 events
✓ Published events logged to: published_events_20251128_143025.xlsx

================================================================================
Waiting 5 seconds before starting subscriber...
================================================================================

STEP 2: Receiving events...
--------------------------------------------------------------------------------
Starting to receive events from Event Hub: my-eventhub
Waiting for 1000 events...
--------------------------------------------------------------------------------
Received 100 events...
Received 200 events...
...
--------------------------------------------------------------------------------
✓ Received 1000 events

Latency Statistics:
  Average: 125.45 ms
  Min: 45.23 ms
  Max: 589.67 ms
✓ Received events logged to: received_events_20251128_143115.xlsx

================================================================================
✓ Test completed successfully!
================================================================================
```

## Azure Event Hub Setup Commands

Create Event Hub using Azure CLI:

```powershell
# Set variables
$rgName = "azure-vinay-mcaps-rg"
$namespace = "vinay-eventhub-ns"
$eventhub = "performance-test"
$location = "uaenorth"

# Create Event Hub namespace
az eventhubs namespace create `
  --name $namespace `
  --resource-group $rgName `
  --location $location `
  --sku Standard

# Create Event Hub
az eventhubs eventhub create `
  --name $eventhub `
  --resource-group $rgName `
  --namespace-name $namespace `
  --partition-count 4 `
  --message-retention 1

# Assign Event Hubs Data Owner role to your user
$userPrincipalName = az account show --query user.name -o tsv
$namespaceId = az eventhubs namespace show `
  --name $namespace `
  --resource-group $rgName `
  --query id -o tsv

az role assignment create `
  --role "Azure Event Hubs Data Owner" `
  --assignee $userPrincipalName `
  --scope $namespaceId

# Get the fully qualified namespace
az eventhubs namespace show `
  --name $namespace `
  --resource-group $rgName `
  --query serviceBusEndpoint -o tsv
```

## Configuration

- **NUM_EVENTS**: Number of events to publish (default: 1000)
- **EVENTHUB_NAMESPACE**: Your Event Hub namespace (e.g., `mynamespace.servicebus.windows.net`)
- **EVENTHUB_NAME**: Name of your Event Hub topic
- **Authentication**: Uses Azure CLI credentials via `DefaultAzureCredential`

## Notes

- Events are sent in batches for better performance
- Subscriber starts from the beginning of the stream (`-1` starting position)
- Default consumer group (`$Default`) is used
- 2-minute timeout for receiving events
- Timestamps are in UTC

## Troubleshooting

1. **Authentication errors**: 
   - Run `az login` to authenticate
   - Verify you have "Azure Event Hubs Data Owner" role assigned
   - Check your namespace format: `namespace.servicebus.windows.net`

2. **Connection errors**: Verify your namespace and Event Hub name are correct

3. **Timeout receiving events**: Increase timeout in `subscriber.py`

4. **Missing events**: Check Event Hub partition count and retention settings

5. **Permission errors**: Ensure you have the required RBAC role:
   ```powershell
   az role assignment list --assignee $(az account show --query user.name -o tsv) --scope /subscriptions/{subscription-id}/resourceGroups/{rg}/providers/Microsoft.EventHub/namespaces/{namespace}
   ```

## Dependencies

- `azure-eventhub`: Azure Event Hub SDK
- `azure-identity`: Azure authentication
- `openpyxl`: Excel file operations
- `python-dotenv`: Environment variable management

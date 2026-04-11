# Redis Geo-Replication Test

Test Azure Cache for Redis geo-replication by writing keys to a primary cache and reading them from a secondary cache in the same replication group.

## Features

- **redis_writer.py**: Writes test keys to primary Redis cache
- **redis_reader.py**: Reads and verifies keys from secondary (replica) Redis cache
- **run_test.py**: Runs complete write → read test sequence
- Performance metrics and statistics
- Replication success rate calculation
- Data integrity verification

## Prerequisites

1. **Azure Cache for Redis** instances in a geo-replication group:
   - Primary cache (write)
   - Secondary cache (read replica)

2. **Python 3.8+** with packages:
   ```powershell
   uv pip install redis python-dotenv
   ```

## Setup

1. **Copy environment template**:
   ```powershell
   Copy-Item .env.example .env
   ```

2. **Configure .env file**:
   ```env
   PRIMARY_REDIS_HOST=your-primary.redis.cache.windows.net
   PRIMARY_REDIS_PASSWORD=your-primary-key
   
   SECONDARY_REDIS_HOST=your-secondary.redis.cache.windows.net
   SECONDARY_REDIS_PASSWORD=your-secondary-key
   
   NUM_TEST_KEYS=100
   RETRY_DELAY_SECONDS=5
   ```

3. **Get Redis credentials from Azure**:
   ```powershell
   # Primary cache
   az redis show --name <primary-cache-name> --resource-group <rg> --query hostName -o tsv
   az redis list-keys --name <primary-cache-name> --resource-group <rg> --query primaryKey -o tsv
   
   # Secondary cache
   az redis show --name <secondary-cache-name> --resource-group <rg> --query hostName -o tsv
   az redis list-keys --name <secondary-cache-name> --resource-group <rg> --query primaryKey -o tsv
   ```

## Usage

### Option 1: Run Complete Test (Recommended)

Runs writer, waits for replication, then runs reader:

```powershell
python run_test.py
```

### Option 2: Run Separately

**Write to primary cache**:
```powershell
python redis_writer.py
```

**Wait for replication** (5-10 seconds recommended)

**Read from secondary cache**:
```powershell
python redis_reader.py
```

### Option 3: Individual Scripts

```powershell
# Write only
python redis_writer.py

# Read only (verify replication)
python redis_reader.py
```

## Output

### Writer Output
```
================================================================================
Redis Cache Writer
================================================================================
Primary Redis Host: mycache-primary.redis.cache.windows.net
Number of keys to write: 100
--------------------------------------------------------------------------------
✓ Connected to primary Redis cache
Writing 100 test keys...
  Written 20 keys...
  Written 40 keys...
  ...
✓ All 100 keys written successfully
--------------------------------------------------------------------------------
Write Statistics:
  Total keys written: 100
  Total time: 0.523 seconds
  Average time per key: 5.23 ms
  Keys per second: 191.20
```

### Reader Output
```
================================================================================
Redis Cache Reader
================================================================================
Secondary Redis Host: mycache-secondary.redis.cache.windows.net
Number of keys to read: 100
--------------------------------------------------------------------------------
✓ Connected to secondary Redis cache
Reading 100 test keys...
  Read 20 keys... (Found: 20)
  ...
✓ Read operation completed
--------------------------------------------------------------------------------
Read Statistics:
  Total keys checked: 100
  Keys found: 100
  Keys missing: 0
  Replication success rate: 100.00%
  Total time: 0.412 seconds
  Average time per key: 4.12 ms
================================================================================
✓ All keys successfully replicated and read!
```

## Key Features

### Data Written
Each test key contains:
- Unique ID
- ISO timestamp
- Test message
- Nested JSON data
- Optional TTL (every 10th key)

### Verification
- Connection testing
- Data integrity checks
- Replication success rate
- Performance metrics
- Missing key detection

### Metadata
Both operations store metadata in Redis:
- `test:metadata:write` - Write operation details
- `test:metadata:read` - Read operation details

## Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| NUM_TEST_KEYS | 100 | Number of keys to write/read |
| RETRY_DELAY_SECONDS | 5 | Wait time for replication |
| PRIMARY_REDIS_PORT | 6380 | Primary cache SSL port |
| SECONDARY_REDIS_PORT | 6380 | Secondary cache SSL port |

## Troubleshooting

### Connection Errors
- Verify Redis hostnames and passwords
- Check Azure firewall rules
- Ensure SSL port 6380 is used

### Missing Keys
- Increase RETRY_DELAY_SECONDS (replication can take 5-30 seconds)
- Check geo-replication status in Azure Portal
- Verify replication link is active

### Performance Issues
- Check Redis cache tier (Standard/Premium)
- Monitor Redis cache metrics
- Consider reducing NUM_TEST_KEYS for testing

## Azure Cache for Redis Setup

### Create Geo-Replication

```powershell
# Create primary cache
az redis create --name mycache-primary --resource-group myRG --location eastus --sku Premium --vm-size P1

# Create secondary cache
az redis create --name mycache-secondary --resource-group myRG --location westus --sku Premium --vm-size P1

# Link for geo-replication (Azure Portal or ARM template)
```

Note: Geo-replication requires **Premium tier** caches.

## Best Practices

1. **Wait for replication**: Allow 5-30 seconds between write and read
2. **Monitor metrics**: Use Azure Monitor for replication lag
3. **Test regularly**: Verify replication is working
4. **Handle failures**: Secondary cache is read-only during failover
5. **Plan failover**: Understand RTO/RPO for your scenario

## License

MIT

"""
Redis Cache Reader - Reads test keys from secondary Redis cache instance
Verifies geo-replication by reading from replica
Uses Azure CLI authentication (DefaultAzureCredential)
"""
import redis
import time
import json
from datetime import datetime
from dotenv import load_dotenv
import os
import subprocess

# Load environment variables
load_dotenv()

def get_redis_token(cache_name):
    """Get Redis access token using Azure CLI"""
    try:
        result = subprocess.run(
            'az account get-access-token --resource https://redis.azure.com',
            capture_output=True,
            text=True,
            check=True,
            shell=True
        )
        token_data = json.loads(result.stdout)
        return token_data['accessToken']
    except Exception as e:
        print(f"ERROR: Failed to get Azure token. Make sure you're logged in with 'az login': {e}")
        raise

def read_test_keys():
    """Read test keys from the secondary (replica) Redis cache"""
    
    # Get configuration from environment
    secondary_host = os.getenv('SECONDARY_REDIS_HOST')
    secondary_cache_name = os.getenv('SECONDARY_REDIS_NAME')
    secondary_port = int(os.getenv('SECONDARY_REDIS_PORT', '6380'))
    num_keys = int(os.getenv('NUM_TEST_KEYS', '100'))
    retry_delay = int(os.getenv('RETRY_DELAY_SECONDS', '5'))
    
    print("=" * 80)
    print("Redis Cache Reader")
    print("=" * 80)
    print(f"Secondary Redis Host: {secondary_host}")
    print(f"Cache Name: {secondary_cache_name}")
    print(f"Number of keys to read: {num_keys}")
    print(f"Retry delay: {retry_delay} seconds")
    print("Using Azure CLI authentication")
    print("-" * 80)
    
    try:
        # Get access token using Azure CLI
        print("Getting Azure access token...")
        access_token = get_redis_token(secondary_cache_name)
        
        # Get user OID for Redis Enterprise authentication
        result = subprocess.run(
            'az ad signed-in-user show --query id -o tsv',
            capture_output=True,
            text=True,
            check=True,
            shell=True
        )
        user_oid = result.stdout.strip()
        print(f"✓ Access token obtained for user: {user_oid}")
        
        # Connect to secondary Redis cache (using RedisCluster for Enterprise)
        print("Connecting to secondary Redis cache...")
        r = redis.RedisCluster(
            host=secondary_host,
            port=secondary_port,
            username=user_oid,
            password=access_token,
            ssl=True,
            ssl_cert_reqs=None,
            decode_responses=True
        )
        
        # Test connection
        r.ping()
        print("✓ Connected to secondary Redis cache")
        print("-" * 80)
        
        # Read test keys with retry logic
        print(f"Reading {num_keys} test keys with retry until all data is replicated...")
        print(f"Initial wait: {retry_delay} seconds")
        print("-" * 80)
        
        time.sleep(retry_delay)
        
        read_times = []
        replication_latencies = []
        read_data = []  # Track read timestamps for export
        found_keys = 0
        missing_keys = []
        retry_count = 0
        max_retries = 100  # Maximum retry attempts
        
        # Keep retrying until all keys are found or max retries reached
        while found_keys < num_keys and retry_count < max_retries:
            if retry_count > 0:
                print(f"\n[Retry {retry_count}] Checking for missing keys... ({len(missing_keys)} missing)")
                time.sleep(retry_delay)
            
            temp_missing = []
            
            for i in range(1, num_keys + 1):
                # Skip keys we've already found (unless first attempt)
                if retry_count > 0 and f"test:key:{i}" not in missing_keys:
                    continue
                
                key = f"test:key:{i}"
                read_start = time.time()
                read_timestamp_dt = datetime.now()
                
                value = r.get(key)
                
                read_end = time.time()
                read_times.append(read_end - read_start)
                
                if value is not None:
                    # Key found!
                    if retry_count == 0 or key in missing_keys:
                        found_keys += 1
                    
                    # Parse and calculate replication latency
                    try:
                        data = json.loads(value)
                        write_timestamp_str = data.get('timestamp')
                        
                        if write_timestamp_str:
                            # Parse write timestamp and calculate latency in milliseconds
                            write_time = datetime.fromisoformat(write_timestamp_str)
                            
                            # Calculate time difference in milliseconds
                            time_diff = read_timestamp_dt - write_time
                            latency_ms = time_diff.total_seconds() * 1000
                            replication_latencies.append(latency_ms)
                            
                            # Format timestamps for display and export
                            write_timestamp_display = write_time.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
                            read_timestamp_display = read_timestamp_dt.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
                            
                            # Store read data for export (only once per key)
                            if retry_count == 0 or key in missing_keys:
                                read_data.append({
                                    "key": key,
                                    "key_number": i,
                                    "write_timestamp": write_timestamp_str,
                                    "write_timestamp_dt": write_timestamp_display,
                                    "read_timestamp": read_timestamp_dt.isoformat(),
                                    "read_timestamp_dt": read_timestamp_display,
                                    "latency_ms": round(latency_ms, 2),
                                    "latency_seconds": round(latency_ms / 1000, 3),
                                    "retry_attempt": retry_count
                                })
                            
                            # Log detailed replication info
                            if retry_count == 0:
                                if i <= 5:  # Show details for first 5 keys
                                    print(f"  {key}:")
                                    print(f"    Written (UAE North):  {write_timestamp_display}")
                                    print(f"    Read (Sweden Central): {read_timestamp_display}")
                                    print(f"    Replication latency: {latency_ms:.2f} ms")
                            else:
                                # Show when previously missing key is now found
                                print(f"  ✓ {key} now available! Latency: {latency_ms:.2f} ms")
                        
                        # Verify data integrity
                        if data.get('id') != i:
                            print(f"  WARNING: Data mismatch for {key}")
                    except json.JSONDecodeError:
                        print(f"  WARNING: Invalid JSON for {key}")
                else:
                    temp_missing.append(key)
                
                # Progress update for first attempt
                if retry_count == 0 and i % 20 == 0:
                    print(f"  Checked {i} keys... (Found: {found_keys})")
            
            missing_keys = temp_missing
            retry_count += 1
            
            if len(missing_keys) == 0:
                print(f"\n✓ All {num_keys} keys found after {retry_count} attempt(s)!")
                break
        
        print(f"✓ Read operation completed")
        print("-" * 80)
        
        # Read statistics
        total_time = sum(read_times)
        avg_time = total_time / len(read_times) if read_times else 0
        
        print(f"Read Statistics:")
        print(f"  Total keys checked: {num_keys}")
        print(f"  Keys found: {found_keys}")
        print(f"  Keys missing: {len(missing_keys)}")
        print(f"  Replication success rate: {(found_keys/num_keys)*100:.2f}%")
        print(f"  Retry attempts: {retry_count}")
        print(f"  Total time: {total_time:.3f} seconds")
        print(f"  Average read time per key: {avg_time*1000:.2f} ms")
        print("-" * 80)
        
        # Replication latency statistics
        if replication_latencies:
            avg_latency = sum(replication_latencies) / len(replication_latencies)
            min_latency = min(replication_latencies)
            max_latency = max(replication_latencies)
            
            print(f"\nGeo-Replication Latency (UAE North → Sweden Central):")
            print(f"  Average: {avg_latency:.2f} ms ({avg_latency/1000:.3f} seconds)")
            print(f"  Minimum: {min_latency:.2f} ms ({min_latency/1000:.3f} seconds)")
            print(f"  Maximum: {max_latency:.2f} ms ({max_latency/1000:.3f} seconds)")
            print(f"  Sample size: {len(replication_latencies)} keys")
            print("-" * 80)
        
        # Check write metadata
        write_metadata = r.get("test:metadata:write")
        if write_metadata:
            print("\nWrite Operation Metadata (replicated):")
            metadata = json.loads(write_metadata)
            for key, value in metadata.items():
                print(f"  {key}: {value}")
            print("✓ Metadata successfully replicated")
        else:
            print("\nWARNING: Write metadata not found (may not be replicated yet)")
        
        # Show missing keys if any
        if missing_keys:
            print(f"\nMissing keys ({len(missing_keys)}):")
            for key in missing_keys[:10]:  # Show first 10
                print(f"  {key}")
            if len(missing_keys) > 10:
                print(f"  ... and {len(missing_keys) - 10} more")
        
        # Display sample replicated data
        print("\nSample replicated keys:")
        for i in [1, 2, 3]:
            key = f"test:key:{i}"
            value = r.get(key)
            if value:
                print(f"  {key}: {value[:100]}...")
            else:
                print(f"  {key}: NOT FOUND")
        
        # Store read metadata
        metadata = {
            "operation": "read",
            "timestamp": datetime.now().isoformat(),
            "total_keys_checked": num_keys,
            "keys_found": found_keys,
            "keys_missing": len(missing_keys),
            "replication_success_rate": (found_keys/num_keys)*100,
            "retry_attempts": retry_count,
            "total_time_seconds": total_time,
            "avg_read_time_ms": avg_time * 1000,
            "avg_replication_latency_ms": sum(replication_latencies) / len(replication_latencies) if replication_latencies else None,
            "min_replication_latency_ms": min(replication_latencies) if replication_latencies else None,
            "max_replication_latency_ms": max(replication_latencies) if replication_latencies else None
        }
        r.set("test:metadata:read", json.dumps(metadata))
        print("\n✓ Read metadata stored")
        
        # Export read timestamps to JSON file
        output_file = "read_timestamps.json"
        with open(output_file, 'w') as f:
            json.dump(read_data, f, indent=2)
        print(f"✓ Read timestamps exported to {output_file}")
        
        print("\n" + "=" * 80)
        if found_keys == num_keys:
            print("✓ All keys successfully replicated and read!")
        else:
            print(f"⚠ Replication incomplete: {found_keys}/{num_keys} keys found")
        print("=" * 80)
        
    except redis.ConnectionError as e:
        print(f"ERROR: Failed to connect to Redis: {e}")
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    read_test_keys()

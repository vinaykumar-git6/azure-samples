"""
Redis Cache Writer - Writes test keys to primary Redis cache instance
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

def write_test_keys():
    """Write test keys to the primary Redis cache"""
    
    # Get configuration from environment
    primary_host = os.getenv('PRIMARY_REDIS_HOST')
    primary_cache_name = os.getenv('PRIMARY_REDIS_NAME')
    primary_port = int(os.getenv('PRIMARY_REDIS_PORT', '6380'))
    num_keys = int(os.getenv('NUM_TEST_KEYS', '100'))
    
    print("=" * 80)
    print("Redis Cache Writer")
    print("=" * 80)
    print(f"Primary Redis Host: {primary_host}")
    print(f"Cache Name: {primary_cache_name}")
    print(f"Number of keys to write: {num_keys}")
    print("Using Azure CLI authentication")
    print("-" * 80)
    
    try:
        # Get access token using Azure CLI
        print("Getting Azure access token...")
        access_token = get_redis_token(primary_cache_name)
        
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
        
        # Connect to primary Redis cache (using RedisCluster for Enterprise)
        print("Connecting to primary Redis cache...")
        r = redis.RedisCluster(
            host=primary_host,
            port=primary_port,
            username=user_oid,
            password=access_token,
            ssl=True,
            ssl_cert_reqs=None,
            decode_responses=True
        )
        
        # Test connection
        r.ping()
        print("✓ Connected to primary Redis cache")
        print("-" * 80)
        
        # Write test keys
        print(f"Writing {num_keys} test keys to UAE North...")
        write_times = []
        write_data = []  # Track write timestamps for export
        write_start_overall = datetime.now()
        
        for i in range(1, num_keys + 1):
            start_time = time.time()
            timestamp = datetime.now()
            timestamp_iso = timestamp.isoformat()
            
            # Create test data with region information
            key = f"test:key:{i}"
            value = json.dumps({
                "id": i,
                "timestamp": timestamp_iso,
                "write_region": "UAE North",
                "message": f"Test message {i}",
                "data": {
                    "value": i * 100,
                    "status": "active"
                }
            })
            
            # Write to Redis
            r.set(key, value)
            
            # Store write timestamp for export
            write_data.append({
                "key": key,
                "key_number": i,
                "write_timestamp": timestamp_iso,
                "write_timestamp_dt": timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
            })
            
            # Also set an expiry for some keys (optional)
            if i % 10 == 0:
                r.expire(key, 3600)  # 1 hour expiry
            
            end_time = time.time()
            write_times.append(end_time - start_time)
            
            # Progress update
            if i % 20 == 0:
                print(f"  Written {i} keys...")
        
        print(f"✓ All {num_keys} keys written successfully")
        print("-" * 80)
        
        # Write statistics
        total_time = sum(write_times)
        avg_time = total_time / len(write_times)
        
        print(f"Write Statistics:")
        print(f"  Total keys written: {num_keys}")
        print(f"  Total time: {total_time:.3f} seconds")
        print(f"  Average time per key: {avg_time*1000:.2f} ms")
        print(f"  Keys per second: {num_keys/total_time:.2f}")
        print("-" * 80)
        
        # Store metadata about the write operation
        write_end_overall = datetime.now()
        metadata = {
            "operation": "write",
            "write_region": "UAE North",
            "start_timestamp": write_start_overall.isoformat(),
            "end_timestamp": write_end_overall.isoformat(),
            "total_keys": num_keys,
            "total_time_seconds": total_time,
            "avg_time_ms": avg_time * 1000,
            "keys_per_second": num_keys / total_time
        }
        r.set("test:metadata:write", json.dumps(metadata))
        print("✓ Write metadata stored")
        
        # Export write timestamps to JSON file
        output_file = "write_timestamps.json"
        with open(output_file, 'w') as f:
            json.dump(write_data, f, indent=2)
        print(f"✓ Write timestamps exported to {output_file}")
        
        # List some sample keys
        print("\nSample keys written:")
        for i in [1, 2, 3]:
            key = f"test:key:{i}"
            value = r.get(key)
            print(f"  {key}: {value[:100]}...")
        
        print("\n" + "=" * 80)
        print("✓ Write operation completed successfully")
        print("=" * 80)
        
    except redis.ConnectionError as e:
        print(f"ERROR: Failed to connect to Redis: {e}")
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    write_test_keys()

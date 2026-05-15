import redis
import subprocess
from azure.identity import AzureCliCredential

# Azure Redis configuration (clustered, access keys disabled, Entra auth required)
REDIS_HOST = "testclustercache.redis.cache.windows.net"
REDIS_PORT = 6380
SCOPE = "https://redis.azure.com/.default"

# Get access token using Azure CLI credential
credential = AzureCliCredential()
token = credential.get_token(SCOPE)

# Get the signed-in user's Object ID for the username
result = subprocess.run(
    "az ad signed-in-user show --query id -o tsv",
    capture_output=True, text=True, shell=True
)
username = result.stdout.strip()

print(f"Connecting to {REDIS_HOST}:{REDIS_PORT} as {username}")

# Connect to Redis over SSL using Entra token
r = redis.StrictRedis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=token.token,
    ssl=True,
    ssl_cert_reqs="required",
    username=username,
    decode_responses=True,
)

# Write a test key
r.set("test-key", "hello-from-azure-cli-cred")
value = r.get("test-key")
print(f"Written and read back: test-key = {value}")

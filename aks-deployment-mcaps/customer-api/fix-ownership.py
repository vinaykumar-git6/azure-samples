"""
Fix ownership of customer schema objects - transfer to customer-api-identity
"""
import psycopg2
from azure.identity import DefaultAzureCredential

PG_HOST = "devpostgresvinay.postgres.database.azure.com"
PG_DATABASE = "postgres"
PG_PORT = 5432
ADMIN_USER = "vinaykumar@microsoft.com"
IDENTITY_NAME = "customer-api-identity"

def run():
    credential = DefaultAzureCredential()
    token = credential.get_token("https://ossrdbms-aad.database.windows.net/.default").token
    print("✓ Token acquired")

    conn = psycopg2.connect(
        host=PG_HOST, database=PG_DATABASE, user=ADMIN_USER,
        password=token, port=PG_PORT, sslmode='require'
    )
    conn.autocommit = True
    cursor = conn.cursor()
    print("✓ Connected to PostgreSQL")

    commands = [
        f'ALTER SCHEMA customer OWNER TO "{IDENTITY_NAME}";',
        f'ALTER TABLE IF EXISTS customer.customers OWNER TO "{IDENTITY_NAME}";',
        f'ALTER SEQUENCE IF EXISTS customer.customers_id_seq OWNER TO "{IDENTITY_NAME}";',
        f'ALTER FUNCTION IF EXISTS customer.update_updated_at_column() OWNER TO "{IDENTITY_NAME}";',
    ]

    for cmd in commands:
        try:
            cursor.execute(cmd)
            print(f"✓ {cmd}")
        except Exception as e:
            print(f"⚠ {cmd}\n  Error: {e}")

    cursor.close()
    conn.close()
    print("\n✓ Ownership transfer complete. Restart pods now.")

if __name__ == "__main__":
    run()

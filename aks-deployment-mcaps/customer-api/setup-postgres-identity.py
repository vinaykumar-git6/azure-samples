"""
Script to add managed identity as PostgreSQL user using Azure AD authentication
"""
import psycopg2
from azure.identity import DefaultAzureCredential
import sys

# Configuration
PG_HOST = "devpostgresvinay.postgres.database.azure.com"
PG_DATABASE = "postgres"
PG_PORT = 5432
ADMIN_USER = "admin@MngEnvMCAP463940.onmicrosoft.com"
MANAGED_IDENTITY_NAME = "customer-api-identity"

def get_azure_ad_token():
    """Get Azure AD token for PostgreSQL"""
    credential = DefaultAzureCredential()
    scope = "https://ossrdbms-aad.database.windows.net/.default"
    token = credential.get_token(scope)
    return token.token

def setup_managed_identity_user():
    """Add managed identity as PostgreSQL user and grant permissions"""
    try:
        print("Getting Azure AD token...")
        token = get_azure_ad_token()
        print("✓ Token acquired successfully")
        
        print(f"\nConnecting to PostgreSQL server: {PG_HOST}")
        conn = psycopg2.connect(
            host=PG_HOST,
            database=PG_DATABASE,
            user=ADMIN_USER,
            password=token,
            port=PG_PORT,
            sslmode='require'
        )
        conn.autocommit = True
        cursor = conn.cursor()
        print("✓ Connected to PostgreSQL")
        
        # Add managed identity as PostgreSQL user
        print(f"\nCreating PostgreSQL user for managed identity: {MANAGED_IDENTITY_NAME}")
        try:
            cursor.execute(f"SELECT * FROM pgaadauth_create_principal('{MANAGED_IDENTITY_NAME}', false, false);")
            result = cursor.fetchone()
            print(f"✓ User created: {result}")
        except psycopg2.errors.DuplicateObject:
            print(f"⚠ User '{MANAGED_IDENTITY_NAME}' already exists")
        except Exception as e:
            print(f"⚠ Note: {e}")
        
        # Grant database privileges
        print(f"\nGranting privileges to '{MANAGED_IDENTITY_NAME}'...")
        
        cursor.execute(f'GRANT ALL PRIVILEGES ON DATABASE {PG_DATABASE} TO "{MANAGED_IDENTITY_NAME}";')
        print("✓ Granted database privileges")
        
        cursor.execute(f'CREATE SCHEMA IF NOT EXISTS customer;')
        print("✓ Created customer schema")
        
        cursor.execute(f'GRANT USAGE ON SCHEMA customer TO "{MANAGED_IDENTITY_NAME}";')
        print("✓ Granted schema usage")
        
        cursor.execute(f'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA customer TO "{MANAGED_IDENTITY_NAME}";')
        print("✓ Granted table privileges")
        
        cursor.execute(f'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA customer TO "{MANAGED_IDENTITY_NAME}";')
        print("✓ Granted sequence privileges")
        
        cursor.execute(f'ALTER DEFAULT PRIVILEGES IN SCHEMA customer GRANT ALL ON TABLES TO "{MANAGED_IDENTITY_NAME}";')
        print("✓ Set default table privileges")
        
        cursor.execute(f'ALTER DEFAULT PRIVILEGES IN SCHEMA customer GRANT ALL ON SEQUENCES TO "{MANAGED_IDENTITY_NAME}";')
        print("✓ Set default sequence privileges")
        
        cursor.execute(f'GRANT CREATE ON SCHEMA customer TO "{MANAGED_IDENTITY_NAME}";')
        print("✓ Granted schema create privilege")
        
        # Verify user exists
        cursor.execute(f"SELECT usename FROM pg_user WHERE usename = '{MANAGED_IDENTITY_NAME}';")
        user = cursor.fetchone()
        if user:
            print(f"\n✓ Verification: User '{user[0]}' exists in PostgreSQL")
        else:
            print(f"\n⚠ Warning: User '{MANAGED_IDENTITY_NAME}' not found")
        
        cursor.close()
        conn.close()
        
        print("\n" + "="*60)
        print("SUCCESS! Managed identity setup complete.")
        print("="*60)
        print("\nNext steps:")
        print("1. Restart the pods: kubectl delete pods -n app -l app=customer-api")
        print("2. Check pod status: kubectl get pods -n app")
        print("3. View logs: kubectl logs <pod-name> -n app")
        
    except Exception as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    setup_managed_identity_user()

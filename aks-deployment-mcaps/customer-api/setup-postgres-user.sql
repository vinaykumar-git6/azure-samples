-- PostgreSQL User Setup for Managed Identity
-- Run these commands after connecting to your PostgreSQL server as an admin user
-- Connection command: psql "host=devpostgresvinay.postgres.database.azure.com port=5432 dbname=postgres user=<your-admin-user> sslmode=require"
-- GET USERNAME of Entra admin
az ad signed-in-user show --query userPrincipalName --output tsv

-- GET access token which can be used as password
$ACCESS_TOKEN=$(az account get-access-token   --resource-type oss-rdbms --query accessToken --output tsv)

-- Add the managed identity as a PostgreSQL user
SELECT * FROM pgaadauth_create_principal('customer-api-identity', false, false);

-- Grant necessary permissions on the database
GRANT ALL PRIVILEGES ON DATABASE postgres TO "customer-api-identity";

-- Connect to the postgres database (if not already connected)
\c postgres

-- Create the customer schema (if not exists)
CREATE SCHEMA IF NOT EXISTS customer;

-- Grant usage on the customer schema
GRANT USAGE ON SCHEMA customer TO "customer-api-identity";

-- Grant permissions on all existing tables in customer schema
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA customer TO "customer-api-identity";

-- Grant permissions on all existing sequences in customer schema
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA customer TO "customer-api-identity";

-- Set default privileges for future tables in customer schema
ALTER DEFAULT PRIVILEGES IN SCHEMA customer GRANT ALL ON TABLES TO "customer-api-identity";

-- Set default privileges for future sequences in customer schema
ALTER DEFAULT PRIVILEGES IN SCHEMA customer GRANT ALL ON SEQUENCES TO "customer-api-identity";

-- Allow the identity to create objects in the customer schema
GRANT CREATE ON SCHEMA customer TO "customer-api-identity";

-- Verify the user was created
SELECT usename FROM pg_user WHERE usename = 'customer-api-identity';

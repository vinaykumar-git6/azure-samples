-- ============================================================================
-- Customer Schema Setup Script
-- Creates the 'customer' schema, table structure, indexes, triggers,
-- and inserts dummy data for the Customer API
-- ============================================================================

-- 1. Create the 'customer' schema
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS customer;

-- 2. Create the customers table under the 'customer' schema
-- ============================================================================
CREATE TABLE IF NOT EXISTS customer.customers (
    id              SERIAL          PRIMARY KEY,
    first_name      VARCHAR(100)    NOT NULL,
    last_name       VARCHAR(100)    NOT NULL,
    email           VARCHAR(255)    UNIQUE NOT NULL,
    phone           VARCHAR(20),
    address         TEXT,
    city            VARCHAR(100),
    country         VARCHAR(100),
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- 3. Create index on email for faster lookups
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_customer_customers_email
    ON customer.customers(email);

-- 4. Create trigger function to auto-update updated_at timestamp
-- ============================================================================
CREATE OR REPLACE FUNCTION customer.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Create trigger on customers table
-- ============================================================================
DROP TRIGGER IF EXISTS update_customers_updated_at ON customer.customers;

CREATE TRIGGER update_customers_updated_at
    BEFORE UPDATE ON customer.customers
    FOR EACH ROW
    EXECUTE FUNCTION customer.update_updated_at_column();

-- 6. Insert dummy data (20 sample customers)
-- ============================================================================
INSERT INTO customer.customers (first_name, last_name, email, phone, address, city, country)
VALUES
    ('John',      'Doe',        'john.doe@example.com',         '+1-212-555-1001', '123 Main St',              'New York',      'USA'),
    ('Jane',      'Smith',      'jane.smith@example.com',       '+1-310-555-1002', '456 Oak Ave',              'Los Angeles',   'USA'),
    ('Ahmed',     'Al-Rashid',  'ahmed.rashid@example.com',     '+971-50-555-1003','789 Palm Jumeirah',        'Dubai',         'UAE'),
    ('Fatima',    'Hassan',     'fatima.hassan@example.com',    '+971-55-555-1004','321 Sheikh Zayed Rd',      'Abu Dhabi',     'UAE'),
    ('Raj',       'Patel',      'raj.patel@example.com',        '+91-98-5551-0005','45 MG Road',               'Mumbai',        'India'),
    ('Priya',     'Sharma',     'priya.sharma@example.com',     '+91-99-5551-0006','12 Connaught Place',       'New Delhi',     'India'),
    ('Emma',      'Wilson',     'emma.wilson@example.com',      '+44-20-5555-1007','10 Baker Street',          'London',        'UK'),
    ('James',     'Brown',      'james.brown@example.com',      '+44-161-555-1008','22 Deansgate',             'Manchester',    'UK'),
    ('Sophie',    'Martin',     'sophie.martin@example.com',    '+33-1-5555-1009', '15 Rue de Rivoli',         'Paris',         'France'),
    ('Lucas',     'Dubois',     'lucas.dubois@example.com',     '+33-4-5555-1010', '8 Avenue Jean Médecin',    'Nice',          'France'),
    ('Yuki',      'Tanaka',     'yuki.tanaka@example.com',      '+81-3-5555-1011', '5-2 Shibuya',              'Tokyo',         'Japan'),
    ('Kenji',     'Nakamura',   'kenji.nakamura@example.com',   '+81-6-5555-1012', '3-1 Namba',                'Osaka',         'Japan'),
    ('Maria',     'Garcia',     'maria.garcia@example.com',     '+34-91-555-1013', 'Calle Gran Via 28',        'Madrid',        'Spain'),
    ('Carlos',    'Rodriguez',  'carlos.rodriguez@example.com', '+34-93-555-1014', 'Passeig de Gracia 55',     'Barcelona',     'Spain'),
    ('Anna',      'Mueller',    'anna.mueller@example.com',     '+49-30-555-1015', 'Unter den Linden 77',      'Berlin',        'Germany'),
    ('Hans',      'Schmidt',    'hans.schmidt@example.com',     '+49-89-555-1016', 'Marienplatz 1',            'Munich',        'Germany'),
    ('Chen',      'Wei',        'chen.wei@example.com',         '+86-10-5555-1017','88 Wangfujing St',         'Beijing',       'China'),
    ('Li',        'Mei',        'li.mei@example.com',           '+86-21-5555-1018','200 Nanjing Rd',           'Shanghai',      'China'),
    ('Omar',      'Khan',       'omar.khan@example.com',        '+92-21-555-1019', '14 Clifton Block 5',       'Karachi',       'Pakistan'),
    ('Sarah',     'O''Connor',  'sarah.oconnor@example.com',    '+353-1-555-1020', '42 Grafton Street',        'Dublin',        'Ireland')
ON CONFLICT (email) DO NOTHING;

-- 7. Grant permissions to the managed identity user (if applicable)
-- ============================================================================
-- Uncomment and run these if using the customer-api-identity managed identity:

-- GRANT USAGE ON SCHEMA customer TO "customer-api-identity";
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA customer TO "customer-api-identity";
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA customer TO "customer-api-identity";
-- ALTER DEFAULT PRIVILEGES IN SCHEMA customer GRANT ALL ON TABLES TO "customer-api-identity";
-- ALTER DEFAULT PRIVILEGES IN SCHEMA customer GRANT ALL ON SEQUENCES TO "customer-api-identity";

-- 8. Verify setup
-- ============================================================================
SELECT 'Schema created' AS status FROM information_schema.schemata WHERE schema_name = 'customer';
SELECT COUNT(*) AS total_customers FROM customer.customers;
SELECT id, first_name, last_name, email, city, country FROM customer.customers ORDER BY id;

"""
Customer REST API Application

A Flask-based REST API for managing customer data in Azure PostgreSQL Flexible Server.
Supports Azure AD authentication and includes comprehensive error handling.

Endpoints:
- POST   /api/customers           - Create a new customer
- GET    /api/customers           - Get all customers
- GET    /api/customers/{id}      - Get customer by ID
- PUT    /api/customers/{id}      - Update customer details
- DELETE /api/customers/{id}      - Delete customer
- GET    /health                  - Health check endpoint
"""

import os
import logging
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2 import pool
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from contextlib import contextmanager
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize Flask application
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Configuration from environment variables
CONFIG = {
    'POSTGRES_HOST': os.getenv('POSTGRES_HOST'),
    'POSTGRES_DATABASE': os.getenv('POSTGRES_DATABASE', 'postgres'),
    'POSTGRES_PORT': int(os.getenv('POSTGRES_PORT', '5432')),
    'POSTGRES_USER': os.getenv('POSTGRES_USER'),
    'POSTGRES_PASSWORD': os.getenv('POSTGRES_PASSWORD'),  # Optional for token auth
    'USE_AZURE_AD': os.getenv('USE_AZURE_AD', 'true').lower() == 'true',
    'MANAGED_IDENTITY_CLIENT_ID': os.getenv('MANAGED_IDENTITY_CLIENT_ID'),  # For AKS pod identity
}

# Global connection pool
connection_pool = None


def get_azure_ad_token():
    """
    Get Azure AD access token for PostgreSQL authentication.
    
    Uses Managed Identity when running in AKS, falls back to DefaultAzureCredential.
    
    Returns:
        str: Access token for PostgreSQL authentication
    """
    try:
        # Use ManagedIdentityCredential in AKS with pod identity
        if CONFIG['MANAGED_IDENTITY_CLIENT_ID']:
            logger.info(f"Using Managed Identity: {CONFIG['MANAGED_IDENTITY_CLIENT_ID']}")
            credential = ManagedIdentityCredential(client_id=CONFIG['MANAGED_IDENTITY_CLIENT_ID'])
        else:
            logger.info("Using DefaultAzureCredential")
            credential = DefaultAzureCredential()
        
        # PostgreSQL resource scope for Azure AD authentication
        scope = "https://ossrdbms-aad.database.windows.net/.default"
        token = credential.get_token(scope)
        
        logger.info("Azure AD token acquired successfully")
        return token.token
    
    except Exception as e:
        logger.error(f"Failed to acquire Azure AD token: {e}")
        raise


def initialize_connection_pool():
    """
    Initialize PostgreSQL connection pool.
    
    Uses Azure AD token authentication if USE_AZURE_AD is true,
    otherwise uses password authentication.
    """
    global connection_pool
    
    try:
        # Get password/token and user based on authentication method
        if CONFIG['USE_AZURE_AD']:
            logger.info("Initializing connection pool with Azure AD authentication")
            password = get_azure_ad_token()
            # When using managed identity, use the identity name as the PostgreSQL user
            if CONFIG['MANAGED_IDENTITY_CLIENT_ID']:
                user = 'customer-api-identity'
                logger.info(f"Using managed identity as PostgreSQL user: {user}")
            else:
                user = CONFIG['POSTGRES_USER']
        else:
            logger.info("Initializing connection pool with password authentication")
            password = CONFIG['POSTGRES_PASSWORD']
            user = CONFIG['POSTGRES_USER']
        
        if not password:
            raise ValueError("No password or token available for authentication")
        
        # Create connection pool
        connection_pool = psycopg2.pool.SimpleConnectionPool(
            minconn=1,
            maxconn=10,
            host=CONFIG['POSTGRES_HOST'],
            port=CONFIG['POSTGRES_PORT'],
            database=CONFIG['POSTGRES_DATABASE'],
            user=user,
            password=password,
            sslmode='require',
            connect_timeout=10
        )
        
        logger.info("Connection pool initialized successfully")
        
        # Initialize database schema
        initialize_database()
        
    except Exception as e:
        logger.error(f"Failed to initialize connection pool: {e}")
        raise


@contextmanager
def get_db_connection():
    """
    Context manager for database connections.
    
    Automatically handles connection acquisition from pool and release.
    Refreshes Azure AD token if expired.
    
    Yields:
        psycopg2.connection: Database connection with RealDictCursor
    """
    conn = None
    try:
        # Get connection from pool
        conn = connection_pool.getconn()
        
        # Set cursor factory for dict-like results
        conn.cursor_factory = RealDictCursor
        
        yield conn
        
    except psycopg2.OperationalError as e:
        # Token might have expired, try to refresh
        if "password authentication failed" in str(e).lower():
            logger.warning("Token expired, refreshing connection pool")
            initialize_connection_pool()
            conn = connection_pool.getconn()
            conn.cursor_factory = RealDictCursor
            yield conn
        else:
            raise
    
    finally:
        # Return connection to pool
        if conn:
            connection_pool.putconn(conn)


def initialize_database():
    """
    Initialize database schema.
    
    Creates the customers table if it doesn't exist.
    """
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                # Create customer schema
                cursor.execute("""
                    CREATE SCHEMA IF NOT EXISTS customer;
                """)
                
                # Create customers table
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS customer.customers (
                        id SERIAL PRIMARY KEY,
                        first_name VARCHAR(100) NOT NULL,
                        last_name VARCHAR(100) NOT NULL,
                        email VARCHAR(255) UNIQUE NOT NULL,
                        phone VARCHAR(20),
                        address TEXT,
                        city VARCHAR(100),
                        country VARCHAR(100),
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    );
                """)
                
                # Create index on email for faster lookups
                cursor.execute("""
                    CREATE INDEX IF NOT EXISTS idx_customers_email 
                    ON customer.customers(email);
                """)
                
                # Create trigger to auto-update updated_at timestamp
                cursor.execute("""
                    CREATE OR REPLACE FUNCTION customer.update_updated_at_column()
                    RETURNS TRIGGER AS $$
                    BEGIN
                        NEW.updated_at = CURRENT_TIMESTAMP;
                        RETURN NEW;
                    END;
                    $$ LANGUAGE plpgsql;
                """)
                
                cursor.execute("""
                    DROP TRIGGER IF EXISTS update_customers_updated_at ON customer.customers;
                """)
                
                cursor.execute("""
                    CREATE TRIGGER update_customers_updated_at
                    BEFORE UPDATE ON customer.customers
                    FOR EACH ROW
                    EXECUTE FUNCTION customer.update_updated_at_column();
                """)
                
                conn.commit()
                logger.info("Database schema initialized successfully")
    
    except Exception as e:
        logger.error(f"Failed to initialize database schema: {e}")
        raise


# ============================================================================
# API Endpoints
# ============================================================================

@app.route('/health', methods=['GET'])
def health_check():
    """
    Health check endpoint.
    
    Returns API status and database connectivity status.
    
    Returns:
        JSON: Health status
    """
    try:
        # Test database connection
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
        
        return jsonify({
            'status': 'healthy',
            'service': 'customer-api',
            'database': 'connected',
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'service': 'customer-api',
            'database': 'disconnected',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 503


@app.route('/api/customers', methods=['POST'])
def create_customer():
    """
    Create a new customer.
    
    Request Body:
        {
            "first_name": "John",
            "last_name": "Doe",
            "email": "john.doe@example.com",
            "phone": "+1234567890",
            "address": "123 Main St",
            "city": "New York",
            "country": "USA"
        }
    
    Returns:
        JSON: Created customer object with HTTP 201
    """
    try:
        # Validate request body
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'Request body is required'}), 400
        
        # Required fields
        required_fields = ['first_name', 'last_name', 'email']
        for field in required_fields:
            if field not in data or not data[field]:
                return jsonify({'error': f'{field} is required'}), 400
        
        # Insert customer into database
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO customer.customers (first_name, last_name, email, phone, address, city, country)
                    VALUES (%(first_name)s, %(last_name)s, %(email)s, %(phone)s, %(address)s, %(city)s, %(country)s)
                    RETURNING id, first_name, last_name, email, phone, address, city, country, 
                              created_at, updated_at
                """, {
                    'first_name': data['first_name'],
                    'last_name': data['last_name'],
                    'email': data['email'],
                    'phone': data.get('phone'),
                    'address': data.get('address'),
                    'city': data.get('city'),
                    'country': data.get('country')
                })
                
                customer = cursor.fetchone()
                conn.commit()
        
        logger.info(f"Customer created: {customer['id']}")
        
        return jsonify(dict(customer)), 201
    
    except psycopg2.IntegrityError as e:
        logger.warning(f"Customer creation failed - duplicate email: {data.get('email')}")
        return jsonify({'error': 'Customer with this email already exists'}), 409
    
    except Exception as e:
        logger.error(f"Failed to create customer: {e}")
        return jsonify({'error': 'Internal server error', 'details': str(e)}), 500


@app.route('/api/customers', methods=['GET'])
def get_all_customers():
    """
    Get all customers with optional filtering and pagination.
    
    Query Parameters:
        - page: Page number (default: 1)
        - limit: Items per page (default: 10, max: 100)
        - city: Filter by city
        - country: Filter by country
    
    Returns:
        JSON: List of customers with pagination metadata
    """
    try:
        # Get query parameters
        page = int(request.args.get('page', 1))
        limit = min(int(request.args.get('limit', 10)), 100)  # Max 100 items per page
        offset = (page - 1) * limit
        
        city = request.args.get('city')
        country = request.args.get('country')
        
        # Build query with filters
        where_clauses = []
        params = {'limit': limit, 'offset': offset}
        
        if city:
            where_clauses.append("city = %(city)s")
            params['city'] = city
        
        if country:
            where_clauses.append("country = %(country)s")
            params['country'] = country
        
        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""
        
        # Get customers
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                # Get total count
                cursor.execute(f"SELECT COUNT(*) as count FROM customer.customers {where_sql}", params)
                total_count = cursor.fetchone()['count']
                
                # Get customers for current page
                cursor.execute(f"""
                    SELECT id, first_name, last_name, email, phone, address, city, country,
                           created_at, updated_at
                    FROM customer.customers
                    {where_sql}
                    ORDER BY created_at DESC
                    LIMIT %(limit)s OFFSET %(offset)s
                """, params)
                
                customers = [dict(row) for row in cursor.fetchall()]
        
        # Calculate pagination metadata
        total_pages = (total_count + limit - 1) // limit
        
        return jsonify({
            'customers': customers,
            'pagination': {
                'page': page,
                'limit': limit,
                'total_items': total_count,
                'total_pages': total_pages,
                'has_next': page < total_pages,
                'has_prev': page > 1
            }
        }), 200
    
    except Exception as e:
        logger.error(f"Failed to get customers: {e}")
        return jsonify({'error': 'Internal server error', 'details': str(e)}), 500


@app.route('/api/customers/<int:customer_id>', methods=['GET'])
def get_customer(customer_id):
    """
    Get customer by ID.
    
    Args:
        customer_id: Customer ID
    
    Returns:
        JSON: Customer object or 404 if not found
    """
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute("""
                    SELECT id, first_name, last_name, email, phone, address, city, country,
                           created_at, updated_at
                    FROM customer.customers
                    WHERE id = %s
                """, (customer_id,))
                
                customer = cursor.fetchone()
        
        if not customer:
            return jsonify({'error': 'Customer not found'}), 404
        
        return jsonify(dict(customer)), 200
    
    except Exception as e:
        logger.error(f"Failed to get customer {customer_id}: {e}")
        return jsonify({'error': 'Internal server error', 'details': str(e)}), 500


@app.route('/api/customers/<int:customer_id>', methods=['PUT'])
def update_customer(customer_id):
    """
    Update customer details.
    
    Args:
        customer_id: Customer ID
    
    Request Body:
        {
            "first_name": "Jane",
            "last_name": "Doe",
            "phone": "+9876543210",
            "address": "456 Oak Ave",
            "city": "Los Angeles",
            "country": "USA"
        }
    
    Returns:
        JSON: Updated customer object or 404 if not found
    """
    try:
        # Validate request body
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'Request body is required'}), 400
        
        # Build update query dynamically based on provided fields
        update_fields = []
        params = {'id': customer_id}
        
        # Fields that can be updated (email is excluded for security)
        updatable_fields = ['first_name', 'last_name', 'phone', 'address', 'city', 'country']
        
        for field in updatable_fields:
            if field in data:
                update_fields.append(f"{field} = %({field})s")
                params[field] = data[field]
        
        if not update_fields:
            return jsonify({'error': 'No valid fields to update'}), 400
        
        # Update customer
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(f"""
                    UPDATE customer.customers
                    SET {', '.join(update_fields)}
                    WHERE id = %(id)s
                    RETURNING id, first_name, last_name, email, phone, address, city, country,
                              created_at, updated_at
                """, params)
                
                customer = cursor.fetchone()
                conn.commit()
        
        if not customer:
            return jsonify({'error': 'Customer not found'}), 404
        
        logger.info(f"Customer updated: {customer_id}")
        
        return jsonify(dict(customer)), 200
    
    except Exception as e:
        logger.error(f"Failed to update customer {customer_id}: {e}")
        return jsonify({'error': 'Internal server error', 'details': str(e)}), 500


@app.route('/api/customers/<int:customer_id>', methods=['DELETE'])
def delete_customer(customer_id):
    """
    Delete customer by ID.
    
    Args:
        customer_id: Customer ID
    
    Returns:
        JSON: Success message or 404 if not found
    """
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute("""
                    DELETE FROM customer.customers
                    WHERE id = %s
                    RETURNING id
                """, (customer_id,))
                
                deleted_customer = cursor.fetchone()
                conn.commit()
        
        if not deleted_customer:
            return jsonify({'error': 'Customer not found'}), 404
        
        logger.info(f"Customer deleted: {customer_id}")
        
        return jsonify({
            'message': 'Customer deleted successfully',
            'id': customer_id
        }), 200
    
    except Exception as e:
        logger.error(f"Failed to delete customer {customer_id}: {e}")
        return jsonify({'error': 'Internal server error', 'details': str(e)}), 500


# ============================================================================
# Application Initialization and Startup
# ============================================================================

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({'error': 'Endpoint not found'}), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors."""
    logger.error(f"Internal server error: {error}")
    return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    # Validate required configuration
    required_config = ['POSTGRES_HOST', 'POSTGRES_USER']
    missing_config = [key for key in required_config if not CONFIG[key]]
    
    if missing_config:
        logger.error(f"Missing required configuration: {', '.join(missing_config)}")
        exit(1)
    
    # Initialize connection pool
    try:
        initialize_connection_pool()
    except Exception as e:
        logger.error(f"Failed to initialize application: {e}")
        exit(1)
    
    # Start Flask application
    port = int(os.getenv('PORT', 5000))
    logger.info(f"Starting Customer API on port {port}")
    
    # Use production WSGI server in container, Flask dev server locally
    if os.getenv('FLASK_ENV') == 'production':
        from waitress import serve
        serve(app, host='0.0.0.0', port=port)
    else:
        app.run(host='0.0.0.0', port=port, debug=True)

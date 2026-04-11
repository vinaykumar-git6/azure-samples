"""
Event Hub to PostgreSQL Service
Consumes Azure Entra ID sign-in events from Event Hub and stores them in PostgreSQL
"""
import os
import json
import logging
import asyncio
from datetime import datetime
from typing import Optional

from azure.eventhub.aio import EventHubConsumerClient
from azure.identity.aio import DefaultAzureCredential
from azure.keyvault.secrets.aio import SecretClient
import asyncpg
from fastapi import FastAPI, HTTPException
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class Config:
    """Application configuration from environment variables"""
    
    def __init__(self):
        # Event Hub Configuration
        self.eventhub_namespace = os.getenv("EVENTHUB_NAMESPACE")
        self.eventhub_name = os.getenv("EVENTHUB_NAME")
        self.consumer_group = os.getenv("CONSUMER_GROUP", "$Default")
        
        # PostgreSQL Configuration
        self.postgres_host = os.getenv("POSTGRES_HOST")
        self.postgres_database = os.getenv("POSTGRES_DATABASE")
        self.postgres_user = os.getenv("POSTGRES_USER")
        
        # Key Vault Configuration
        self.keyvault_url = os.getenv("KEYVAULT_URL")
        self.postgres_password_secret = os.getenv("POSTGRES_PASSWORD_SECRET_NAME", "postgres-password")
        
        # Application Configuration
        self.batch_size = int(os.getenv("BATCH_SIZE", "100"))
        self.max_wait_time = int(os.getenv("MAX_WAIT_TIME", "60"))
        
    def validate(self):
        """Validate required configuration"""
        required = {
            "EVENTHUB_NAMESPACE": self.eventhub_namespace,
            "EVENTHUB_NAME": self.eventhub_name,
            "POSTGRES_HOST": self.postgres_host,
            "POSTGRES_DATABASE": self.postgres_database,
            "POSTGRES_USER": self.postgres_user,
            "KEYVAULT_URL": self.keyvault_url
        }
        
        missing = [k for k, v in required.items() if not v]
        if missing:
            raise ValueError(f"Missing required environment variables: {', '.join(missing)}")


class EventProcessor:
    """Processes events from Event Hub and stores in PostgreSQL"""
    
    def __init__(self, config: Config):
        self.config = config
        self.credential = None
        self.pg_pool = None
        self.eventhub_client = None
        self.postgres_password = None
        
    async def initialize(self):
        """Initialize connections"""
        logger.info("Initializing Event Processor...")
        
        # Initialize Azure credential
        self.credential = DefaultAzureCredential()
        
        # Get PostgreSQL password from Key Vault
        await self._get_postgres_password()
        
        # Initialize PostgreSQL connection pool
        await self._init_postgres_pool()
        
        # Create table if not exists
        await self._create_table()
        
        # Initialize Event Hub client
        self._init_eventhub_client()
        
        logger.info("Event Processor initialized successfully")
    
    async def _get_postgres_password(self):
        """Retrieve PostgreSQL password from Key Vault"""
        try:
            logger.info("Retrieving PostgreSQL password from Key Vault...")
            secret_client = SecretClient(
                vault_url=self.config.keyvault_url,
                credential=self.credential
            )
            
            secret = await secret_client.get_secret(self.config.postgres_password_secret)
            self.postgres_password = secret.value
            
            await secret_client.close()
            logger.info("PostgreSQL password retrieved successfully")
            
        except Exception as e:
            logger.error(f"Failed to retrieve password from Key Vault: {e}")
            raise
    
    async def _init_postgres_pool(self):
        """Initialize PostgreSQL connection pool"""
        try:
            logger.info("Connecting to PostgreSQL...")
            self.pg_pool = await asyncpg.create_pool(
                host=self.config.postgres_host,
                database=self.config.postgres_database,
                user=self.config.postgres_user,
                password=self.postgres_password,
                min_size=2,
                max_size=10,
                command_timeout=60
            )
            logger.info("PostgreSQL connection pool created")
            
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL: {e}")
            raise
    
    async def _create_table(self):
        """Create sign-in events table if not exists"""
        create_table_sql = """
        CREATE TABLE IF NOT EXISTS signin_events (
            id SERIAL PRIMARY KEY,
            event_id VARCHAR(255) UNIQUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            user_principal_name VARCHAR(255),
            user_id VARCHAR(255),
            app_display_name VARCHAR(255),
            app_id VARCHAR(255),
            ip_address VARCHAR(45),
            location VARCHAR(255),
            status VARCHAR(50),
            sign_in_time TIMESTAMP,
            risk_level VARCHAR(50),
            device_detail JSONB,
            raw_event JSONB NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_signin_events_user_id ON signin_events(user_id);
        CREATE INDEX IF NOT EXISTS idx_signin_events_sign_in_time ON signin_events(sign_in_time);
        CREATE INDEX IF NOT EXISTS idx_signin_events_status ON signin_events(status);
        """
        
        async with self.pg_pool.acquire() as conn:
            await conn.execute(create_table_sql)
            logger.info("Database table and indexes verified")
    
    def _init_eventhub_client(self):
        """Initialize Event Hub consumer client"""
        eventhub_fqdn = f"{self.config.eventhub_namespace}.servicebus.windows.net"
        
        self.eventhub_client = EventHubConsumerClient(
            fully_qualified_namespace=eventhub_fqdn,
            eventhub_name=self.config.eventhub_name,
            consumer_group=self.config.consumer_group,
            credential=self.credential
        )
        logger.info(f"Event Hub client initialized for {eventhub_fqdn}/{self.config.eventhub_name}")
    
    async def process_event(self, partition_context, event):
        """Process a single event from Event Hub"""
        try:
            # Parse event body
            event_data = json.loads(event.body_as_str())
            
            # Extract relevant fields from Entra ID sign-in event
            event_id = event_data.get("id")
            user_principal = event_data.get("userPrincipalName", "")
            user_id = event_data.get("userId", "")
            app_name = event_data.get("appDisplayName", "")
            app_id = event_data.get("appId", "")
            ip_address = event_data.get("ipAddress", "")
            location = event_data.get("location", {}).get("city", "")
            status = event_data.get("status", {}).get("errorCode", "0")
            sign_in_time_str = event_data.get("createdDateTime", "")
            risk_level = event_data.get("riskLevelDuringSignIn", "none")
            device_detail = json.dumps(event_data.get("deviceDetail", {}))
            
            # Parse sign-in time
            sign_in_time = None
            if sign_in_time_str:
                try:
                    sign_in_time = datetime.fromisoformat(sign_in_time_str.replace('Z', '+00:00'))
                except:
                    pass
            
            # Insert into PostgreSQL
            async with self.pg_pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO signin_events 
                    (event_id, user_principal_name, user_id, app_display_name, app_id, 
                     ip_address, location, status, sign_in_time, risk_level, device_detail, raw_event)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                    ON CONFLICT (event_id) DO NOTHING
                    """,
                    event_id, user_principal, user_id, app_name, app_id,
                    ip_address, location, str(status), sign_in_time, risk_level,
                    device_detail, json.dumps(event_data)
                )
            
            # Update checkpoint
            await partition_context.update_checkpoint(event)
            
            logger.debug(f"Processed event: {event_id} for user: {user_principal}")
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse event JSON: {e}")
        except Exception as e:
            logger.error(f"Error processing event: {e}", exc_info=True)
    
    async def start_processing(self):
        """Start consuming events from Event Hub"""
        try:
            logger.info("Starting Event Hub consumer...")
            
            async with self.eventhub_client:
                await self.eventhub_client.receive(
                    on_event=self.process_event,
                    max_wait_time=self.config.max_wait_time,
                    starting_position="-1"  # Start from beginning or last checkpoint
                )
                
        except KeyboardInterrupt:
            logger.info("Event processing stopped by user")
        except Exception as e:
            logger.error(f"Error in event processing: {e}", exc_info=True)
            raise
    
    async def cleanup(self):
        """Cleanup resources"""
        logger.info("Cleaning up resources...")
        
        if self.eventhub_client:
            await self.eventhub_client.close()
        
        if self.pg_pool:
            await self.pg_pool.close()
        
        if self.credential:
            await self.credential.close()
        
        logger.info("Cleanup completed")


# Global processor instance
processor: Optional[EventProcessor] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    global processor
    
    # Startup
    config = Config()
    config.validate()
    
    processor = EventProcessor(config)
    await processor.initialize()
    
    # Start event processing in background
    asyncio.create_task(processor.start_processing())
    
    yield
    
    # Shutdown
    if processor:
        await processor.cleanup()


# FastAPI application
app = FastAPI(
    title="Event Hub to PostgreSQL Service",
    description="Processes Azure Entra ID sign-in events from Event Hub and stores in PostgreSQL",
    version="1.0.0",
    lifespan=lifespan
)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "eventhub-postgres-service",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/stats")
async def get_stats():
    """Get statistics about processed events"""
    if not processor or not processor.pg_pool:
        raise HTTPException(status_code=503, detail="Service not initialized")
    
    try:
        async with processor.pg_pool.acquire() as conn:
            total_events = await conn.fetchval("SELECT COUNT(*) FROM signin_events")
            
            recent_events = await conn.fetchval(
                """
                SELECT COUNT(*) FROM signin_events 
                WHERE created_at > NOW() - INTERVAL '1 hour'
                """
            )
            
            unique_users = await conn.fetchval(
                "SELECT COUNT(DISTINCT user_id) FROM signin_events"
            )
            
            return {
                "total_events": total_events,
                "recent_events_1h": recent_events,
                "unique_users": unique_users,
                "timestamp": datetime.utcnow().isoformat()
            }
            
    except Exception as e:
        logger.error(f"Error fetching stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    
    # Run with uvicorn
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )

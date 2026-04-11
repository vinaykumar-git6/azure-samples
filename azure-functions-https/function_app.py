"""Azure Functions app for Cosmos DB customer account CRUD operations.""""""Azure Functions app for Cosmos DB customer account CRUD operations.""""""Azure Functions app for Cosmos DB customer account CRUD operations."""



import azure.functions as funcimport azure.functions as funcimport azure.functions as func

import json

import loggingimport jsonimport json

from datetime import datetime

from models import CustomerAccount, CustomerAccountResponseimport loggingimport logging

from cosmos_db import CosmosDBClient

from datetime import datetimefrom datetime import datetime

# Configure logging

logging.basicConfig(level=logging.INFO)import osfrom models import CustomerAccount, CustomerAccountResponse

logger = logging.getLogger(__name__)

import sysfrom cosmos_db import CosmosDBClient

# Create Function App

app = func.FunctionApp()



# Initialize Cosmos DB client (singleton pattern)# Add parent directory to path for imports# Configure logging

_cosmos_client = None

sys.path.append(os.path.dirname(__file__))logging.basicConfig(level=logging.INFO)

def get_cosmos_client() -> CosmosDBClient:

    """Get or create Cosmos DB client instance."""logger = logging.getLogger(__name__)

    global _cosmos_client

    if _cosmos_client is None:from models import CustomerAccount, CustomerAccountResponse

        import os

        endpoint = os.environ.get("COSMOS_ENDPOINT")from cosmos_db import CosmosDBClient# Create Function App

        key = os.environ.get("COSMOS_KEY")

        database_name = os.environ.get("COSMOS_DATABASE")app = func.FunctionApp()

        container_name = os.environ.get("COSMOS_CONTAINER")

        # Configure logging

        if not all([endpoint, key, database_name, container_name]):

            raise ValueError("Missing required Cosmos DB environment variables")logging.basicConfig(level=logging.INFO)# Initialize Cosmos DB client (singleton pattern)

        

        _cosmos_client = CosmosDBClient(endpoint, key, database_name, container_name)logger = logging.getLogger(__name__)_cosmos_client = None

        logger.info("Cosmos DB client initialized successfully")

    

    return _cosmos_client

# Create Function App



@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)app = func.FunctionApp()def get_cosmos_client() -> CosmosDBClient:

def health_check(req: func.HttpRequest) -> func.HttpResponse:

    """Health check endpoint."""	"""Get or initialize Cosmos DB client (lazy initialization)."""

    logger.info("Health check endpoint called")

    # Initialize Cosmos DB client (singleton pattern)	global _cosmos_client

    response_data = {

        "success": True,_cosmos_client = None	if _cosmos_client is None:

        "message": "Function App is healthy",

        "timestamp": datetime.utcnow().isoformat()		_cosmos_client = CosmosDBClient()

    }

    	return _cosmos_client

    return func.HttpResponse(

        body=json.dumps(response_data),def get_cosmos_client() -> CosmosDBClient:

        mimetype="application/json",

        status_code=200	"""Get or initialize Cosmos DB client (lazy initialization)."""

    )

	global _cosmos_client@app.route(route="customers", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)



@app.route(route="customers", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)	if _cosmos_client is None:def create_customer(req: func.HttpRequest) -> func.HttpResponse:

def create_customer(req: func.HttpRequest) -> func.HttpResponse:

    """Create a new customer account."""		endpoint = os.getenv('COSMOS_ENDPOINT')	"""Create a new customer account.

    logger.info("Create customer endpoint called")

    		key = os.getenv('COSMOS_KEY')

    try:

        # Parse request body		database = os.getenv('COSMOS_DATABASE', 'CustomerDB')	Expected JSON body:

        req_body = req.get_json()

        logger.info(f"Received customer data: {req_body}")		container = os.getenv('COSMOS_CONTAINER', 'Accounts')	{

        

        # Validate using Pydantic model				"id": "cust-001",

        customer = CustomerAccount(**req_body)

        		if not endpoint or not key:		"name": "John Doe",

        # Add timestamps

        customer_dict = customer.model_dump()			logger.error("COSMOS_ENDPOINT or COSMOS_KEY not set")		"email": "john@example.com",

        customer_dict["created_at"] = datetime.utcnow().isoformat()

        customer_dict["updated_at"] = datetime.utcnow().isoformat()			raise ValueError("Cosmos DB credentials not configured")		"phone": "+1-555-0123",

        

        # Save to Cosmos DB				"account_type": "premium",

        cosmos_client = get_cosmos_client()

        created_item = cosmos_client.create_item(customer_dict)		_cosmos_client = CosmosDBClient(endpoint, key, database, container)		"status": "active",

        

        # Prepare response			"balance": 5000.00

        response = CustomerAccountResponse(

            success=True,	return _cosmos_client	}

            message="Customer account created successfully",

            data=CustomerAccount(**created_item)	"""

        )

        	try:

        logger.info(f"Customer created successfully: {customer.id}")

        @app.route("api/health", methods=["GET"])		req_body = req.get_json()

        return func.HttpResponse(

            body=response.model_dump_json(),def health_check(req: func.HttpRequest) -> func.HttpResponse:		customer = CustomerAccount(**req_body)

            mimetype="application/json",

            status_code=201	"""Health check endpoint."""

        )

        	try:		# Add timestamps

    except ValueError as e:

        logger.error(f"Validation error: {str(e)}")		logger.info("Health check requested")		now = datetime.utcnow().isoformat()

        error_response = CustomerAccountResponse(

            success=False,		response_data = {		customer_dict = customer.model_dump()

            message="Validation error",

            error=str(e)			"success": True,		customer_dict["created_at"] = now

        )

        return func.HttpResponse(			"message": "Function App is healthy",		customer_dict["updated_at"] = now

            body=error_response.model_dump_json(),

            mimetype="application/json",			"timestamp": datetime.utcnow().isoformat()

            status_code=400

        )		}		# Create in Cosmos DB

    

    except Exception as e:		return func.HttpResponse(		cosmos = get_cosmos_client()

        logger.error(f"Error creating customer: {str(e)}")

        error_response = CustomerAccountResponse(			json.dumps(response_data),		result = cosmos.create_item(customer_dict)

            success=False,

            message="Error creating customer",			status_code=200,

            error=str(e)

        )			mimetype="application/json"		response = CustomerAccountResponse(

        return func.HttpResponse(

            body=error_response.model_dump_json(),		)			success=True,

            mimetype="application/json",

            status_code=500	except Exception as e:			message="Customer account created successfully",

        )

		logger.error(f"Health check error: {str(e)}")			data=result,



@app.route(route="customers/{id}", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)		return func.HttpResponse(		)

def get_customer(req: func.HttpRequest) -> func.HttpResponse:

    """Get a customer account by ID."""			json.dumps({"success": False, "error": str(e)}),		return func.HttpResponse(

    customer_id = req.route_params.get('id')

    logger.info(f"Get customer endpoint called for ID: {customer_id}")			status_code=500,			response.model_dump_json(),

    

    try:			mimetype="application/json"			status_code=201,

        cosmos_client = get_cosmos_client()

        customer_data = cosmos_client.read_item(customer_id, customer_id)		)			mimetype="application/json",

        

        if customer_data:		)

            response = CustomerAccountResponse(

                success=True,

                message="Customer account retrieved successfully",

                data=CustomerAccount(**customer_data)@app.route("api/customers", methods=["POST"])	except ValueError as e:

            )

            return func.HttpResponse(def create_customer(req: func.HttpRequest) -> func.HttpResponse:		logger.warning(f"Validation error: {e}")

                body=response.model_dump_json(),

                mimetype="application/json",	"""Create a new customer account."""		response = CustomerAccountResponse(

                status_code=200

            )	try:			success=False,

        else:

            error_response = CustomerAccountResponse(		logger.info("Creating new customer")			message="Validation failed",

                success=False,

                message=f"Customer with ID {customer_id} not found",		body = req.get_json()			error=str(e),

                error="Not found"

            )				)

            return func.HttpResponse(

                body=error_response.model_dump_json(),		# Validate input		return func.HttpResponse(

                mimetype="application/json",

                status_code=404		customer_data = CustomerAccount(**body)			response.model_dump_json(),

            )

    					status_code=400,

    except Exception as e:

        logger.error(f"Error getting customer: {str(e)}")		# Save to Cosmos DB			mimetype="application/json",

        error_response = CustomerAccountResponse(

            success=False,		cosmos_client = get_cosmos_client()		)

            message="Error retrieving customer",

            error=str(e)		cosmos_client.create_item(customer_data.model_dump())	except Exception as e:

        )

        return func.HttpResponse(				logger.error(f"Error creating customer: {e}")

            body=error_response.model_dump_json(),

            mimetype="application/json",		response = CustomerAccountResponse(		response = CustomerAccountResponse(

            status_code=500

        )			success=True,			success=False,



			message="Customer created successfully",			message="Error creating customer account",

@app.route(route="customers/{id}", methods=["PUT"], auth_level=func.AuthLevel.ANONYMOUS)

def update_customer(req: func.HttpRequest) -> func.HttpResponse:			data=customer_data			error=str(e),

    """Update a customer account."""

    customer_id = req.route_params.get('id')		)		)

    logger.info(f"Update customer endpoint called for ID: {customer_id}")

    				return func.HttpResponse(

    try:

        # Parse request body		return func.HttpResponse(			response.model_dump_json(),

        req_body = req.get_json()

        logger.info(f"Received update data: {req_body}")			response.model_dump_json(),			status_code=500,

        

        # Update in Cosmos DB			status_code=201,			mimetype="application/json",

        cosmos_client = get_cosmos_client()

        updated_item = cosmos_client.update_item(customer_id, customer_id, req_body)			mimetype="application/json"		)

        

        if updated_item:		)

            response = CustomerAccountResponse(

                success=True,	except Exception as e:

                message="Customer account updated successfully",

                data=CustomerAccount(**updated_item)		logger.error(f"Create customer error: {str(e)}")@app.route(route="customers/{customer_id}", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)

            )

            return func.HttpResponse(		return func.HttpResponse(def get_customer(req: func.HttpRequest) -> func.HttpResponse:

                body=response.model_dump_json(),

                mimetype="application/json",			json.dumps({"success": False, "error": str(e)}),	"""Fetch a customer account by ID.

                status_code=200

            )			status_code=400,

        else:

            error_response = CustomerAccountResponse(			mimetype="application/json"	URL parameters:

                success=False,

                message=f"Customer with ID {customer_id} not found",		)		customer_id: The customer ID to retrieve

                error="Not found"

            )	"""

            return func.HttpResponse(

                body=error_response.model_dump_json(),	try:

                mimetype="application/json",

                status_code=404@app.route("api/customers/{id}", methods=["GET"])		customer_id = req.route_params.get("customer_id")

            )

    def get_customer(req: func.HttpRequest) -> func.HttpResponse:		if not customer_id:

    except Exception as e:

        logger.error(f"Error updating customer: {str(e)}")	"""Get a customer by ID."""			raise ValueError("customer_id is required")

        error_response = CustomerAccountResponse(

            success=False,	try:

            message="Error updating customer",

            error=str(e)		customer_id = req.route_params.get("id")		cosmos = get_cosmos_client()

        )

        return func.HttpResponse(		logger.info(f"Getting customer: {customer_id}")		# Use customer_id as both ID and partition key

            body=error_response.model_dump_json(),

            mimetype="application/json",				result = cosmos.read_item(customer_id, partition_key=customer_id)

            status_code=500

        )		cosmos_client = get_cosmos_client()



		item = cosmos_client.read_item(customer_id)		response = CustomerAccountResponse(

@app.route(route="customers", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)

def list_customers(req: func.HttpRequest) -> func.HttpResponse:					success=True,

    """List all customer accounts with optional filtering."""

    logger.info("List customers endpoint called")		if not item:			message="Customer account retrieved successfully",

    

    try:			return func.HttpResponse(			data=result,

        # Get query parameters

        status = req.params.get('status')				json.dumps({"success": False, "error": "Customer not found"}),		)

        

        # Build query				status_code=404,		return func.HttpResponse(

        if status:

            query = "SELECT * FROM c WHERE c.status = @status"				mimetype="application/json"			response.model_dump_json(),

            parameters = [{"name": "@status", "value": status}]

        else:			)			status_code=200,

            query = "SELECT * FROM c"

            parameters = None					mimetype="application/json",

        

        # Query Cosmos DB		response = CustomerAccountResponse(		)

        cosmos_client = get_cosmos_client()

        customers_data = cosmos_client.query_items(query, parameters)			success=True,

        

        # Convert to Pydantic models			message="Customer retrieved successfully",	except ValueError as e:

        customers = [CustomerAccount(**item) for item in customers_data]

        			data=CustomerAccount(**item)		logger.warning(f"Validation error: {e}")

        response_data = {

            "success": True,		)		response = CustomerAccountResponse(

            "message": f"Retrieved {len(customers)} customer accounts",

            "count": len(customers),					success=False,

            "data": [customer.model_dump() for customer in customers]

        }		return func.HttpResponse(			message="Customer not found",

        

        return func.HttpResponse(			response.model_dump_json(),			error=str(e),

            body=json.dumps(response_data),

            mimetype="application/json",			status_code=200,		)

            status_code=200

        )			mimetype="application/json"		return func.HttpResponse(

    

    except Exception as e:		)			response.model_dump_json(),

        logger.error(f"Error listing customers: {str(e)}")

        error_response = {	except Exception as e:			status_code=404,

            "success": False,

            "message": "Error listing customers",		logger.error(f"Get customer error: {str(e)}")			mimetype="application/json",

            "error": str(e)

        }		return func.HttpResponse(		)

        return func.HttpResponse(

            body=json.dumps(error_response),			json.dumps({"success": False, "error": str(e)}),	except Exception as e:

            mimetype="application/json",

            status_code=500			status_code=500,		logger.error(f"Error retrieving customer: {e}")

        )

			mimetype="application/json"		response = CustomerAccountResponse(

		)			success=False,

			message="Error retrieving customer account",

			error=str(e),

@app.route("api/customers/{id}", methods=["PUT"])		)

def update_customer(req: func.HttpRequest) -> func.HttpResponse:		return func.HttpResponse(

	"""Update a customer."""			response.model_dump_json(),

	try:			status_code=500,

		customer_id = req.route_params.get("id")			mimetype="application/json",

		update_data = req.get_json()		)

		logger.info(f"Updating customer: {customer_id}")

		

		cosmos_client = get_cosmos_client()@app.route(route="customers/{customer_id}", methods=["PUT"], auth_level=func.AuthLevel.FUNCTION)

		updated_item = cosmos_client.update_item(customer_id, update_data)def update_customer(req: func.HttpRequest) -> func.HttpResponse:

			"""Update an existing customer account.

		response = CustomerAccountResponse(

			success=True,	URL parameters:

			message="Customer updated successfully",		customer_id: The customer ID to update

			data=CustomerAccount(**updated_item)

		)	Expected JSON body (partial update):

			{

		return func.HttpResponse(		"name": "Jane Doe",

			response.model_dump_json(),		"email": "jane@example.com",

			status_code=200,		"balance": 7500.00

			mimetype="application/json"	}

		)	"""

	except Exception as e:	try:

		logger.error(f"Update customer error: {str(e)}")		customer_id = req.route_params.get("customer_id")

		return func.HttpResponse(		if not customer_id:

			json.dumps({"success": False, "error": str(e)}),			raise ValueError("customer_id is required")

			status_code=400,

			mimetype="application/json"		cosmos = get_cosmos_client()

		)		# First, get the existing item

		existing = cosmos.read_item(customer_id, partition_key=customer_id)



@app.route("api/customers", methods=["GET"])		# Merge with updates

def list_customers(req: func.HttpRequest) -> func.HttpResponse:		req_body = req.get_json()

	"""List all customers (with optional status filter)."""		existing.update(req_body)

	try:		existing["updated_at"] = datetime.utcnow().isoformat()

		status_filter = req.params.get("status")

		logger.info(f"Listing customers (filter: {status_filter})")		# Validate the merged object

				CustomerAccount(**existing)

		cosmos_client = get_cosmos_client()

				# Update in Cosmos DB

		if status_filter:		result = cosmos.update_item(customer_id, partition_key=customer_id, item=existing)

			query = f"SELECT * FROM c WHERE c.status = @status"

			items = cosmos_client.query_items(query, {"@status": status_filter})		response = CustomerAccountResponse(

		else:			success=True,

			items = cosmos_client.query_items("SELECT * FROM c")			message="Customer account updated successfully",

					data=result,

		customers = [CustomerAccount(**item) for item in items]		)

				return func.HttpResponse(

		response_data = {			response.model_dump_json(),

			"success": True,			status_code=200,

			"message": f"Retrieved {len(customers)} customers",			mimetype="application/json",

			"count": len(customers),		)

			"data": [c.model_dump() for c in customers]

		}	except ValueError as e:

				logger.warning(f"Validation or not found error: {e}")

		return func.HttpResponse(		response = CustomerAccountResponse(

			json.dumps(response_data),			success=False,

			status_code=200,			message="Customer not found or validation failed",

			mimetype="application/json"			error=str(e),

		)		)

	except Exception as e:		return func.HttpResponse(

		logger.error(f"List customers error: {str(e)}")			response.model_dump_json(),

		return func.HttpResponse(			status_code=404,

			json.dumps({"success": False, "error": str(e)}),			mimetype="application/json",

			status_code=500,		)

			mimetype="application/json"	except Exception as e:

		)		logger.error(f"Error updating customer: {e}")

		response = CustomerAccountResponse(
			success=False,
			message="Error updating customer account",
			error=str(e),
		)
		return func.HttpResponse(
			response.model_dump_json(),
			status_code=500,
			mimetype="application/json",
		)


@app.route(route="customers", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def list_customers(req: func.HttpRequest) -> func.HttpResponse:
	"""List all customer accounts (with optional filtering).

	Query parameters:
		status: Filter by account status (active, inactive, suspended)
	"""
	try:
		cosmos = get_cosmos_client()
		status_filter = req.params.get("status")

		if status_filter:
			query = "SELECT * FROM c WHERE c.status = @status"
			parameters = [{"name": "@status", "value": status_filter}]
			items = cosmos.query_items(query, parameters=parameters)
		else:
			query = "SELECT * FROM c"
			items = cosmos.query_items(query)

		response = CustomerAccountResponse(
			success=True,
			message=f"Retrieved {len(items)} customer accounts",
			data={"customers": items, "count": len(items)},
		)
		return func.HttpResponse(
			response.model_dump_json(),
			status_code=200,
			mimetype="application/json",
		)

	except Exception as e:
		logger.error(f"Error listing customers: {e}")
		response = CustomerAccountResponse(
			success=False,
			message="Error listing customer accounts",
			error=str(e),
		)
		return func.HttpResponse(
			response.model_dump_json(),
			status_code=500,
			mimetype="application/json",
		)


@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
	"""Health check endpoint."""
	return func.HttpResponse(
		json.dumps({"status": "healthy", "service": "Customer Account Service"}),
		status_code=200,
		mimetype="application/json",
	)

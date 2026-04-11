"""Azure Functions app for Cosmos DB customer account CRUD operations.""""""Azure Functions app for Cosmos DB customer account CRUD operations."""

import azure.functions as funcimport azure.functions as func

import jsonimport json

import loggingimport logging

from datetime import datetimefrom datetime import datetime

import osfrom models import CustomerAccount, CustomerAccountResponse

import sysfrom cosmos_db import CosmosDBClient



# Add parent directory to path for imports# Configure logging

sys.path.append(os.path.dirname(__file__))logging.basicConfig(level=logging.INFO)

logger = logging.getLogger(__name__)

from models import CustomerAccount, CustomerAccountResponse

from cosmos_db import CosmosDBClient# Create Function App

app = func.FunctionApp()

# Configure logging

logging.basicConfig(level=logging.INFO)# Initialize Cosmos DB client (singleton pattern)

logger = logging.getLogger(__name__)_cosmos_client = None



# Create Function App

app = func.FunctionApp()def get_cosmos_client() -> CosmosDBClient:

	"""Get or initialize Cosmos DB client (lazy initialization)."""

# Initialize Cosmos DB client (singleton pattern)	global _cosmos_client

_cosmos_client = None	if _cosmos_client is None:

		_cosmos_client = CosmosDBClient()

	return _cosmos_client

def get_cosmos_client() -> CosmosDBClient:

	"""Get or initialize Cosmos DB client (lazy initialization)."""

	global _cosmos_client@app.route(route="customers", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)

	if _cosmos_client is None:def create_customer(req: func.HttpRequest) -> func.HttpResponse:

		endpoint = os.getenv('COSMOS_ENDPOINT')	"""Create a new customer account.

		key = os.getenv('COSMOS_KEY')

		database = os.getenv('COSMOS_DATABASE', 'CustomerDB')	Expected JSON body:

		container = os.getenv('COSMOS_CONTAINER', 'Accounts')	{

				"id": "cust-001",

		if not endpoint or not key:		"name": "John Doe",

			logger.error("COSMOS_ENDPOINT or COSMOS_KEY not set")		"email": "john@example.com",

			raise ValueError("Cosmos DB credentials not configured")		"phone": "+1-555-0123",

				"account_type": "premium",

		_cosmos_client = CosmosDBClient(endpoint, key, database, container)		"status": "active",

			"balance": 5000.00

	return _cosmos_client	}

	"""

	try:

@app.route("api/health", methods=["GET"])		req_body = req.get_json()

def health_check(req: func.HttpRequest) -> func.HttpResponse:		customer = CustomerAccount(**req_body)

	"""Health check endpoint."""

	try:		# Add timestamps

		logger.info("Health check requested")		now = datetime.utcnow().isoformat()

		response_data = {		customer_dict = customer.model_dump()

			"success": True,		customer_dict["created_at"] = now

			"message": "Function App is healthy",		customer_dict["updated_at"] = now

			"timestamp": datetime.utcnow().isoformat()

		}		# Create in Cosmos DB

		return func.HttpResponse(		cosmos = get_cosmos_client()

			json.dumps(response_data),		result = cosmos.create_item(customer_dict)

			status_code=200,

			mimetype="application/json"		response = CustomerAccountResponse(

		)			success=True,

	except Exception as e:			message="Customer account created successfully",

		logger.error(f"Health check error: {str(e)}")			data=result,

		return func.HttpResponse(		)

			json.dumps({"success": False, "error": str(e)}),		return func.HttpResponse(

			status_code=500,			response.model_dump_json(),

			mimetype="application/json"			status_code=201,

		)			mimetype="application/json",

		)



@app.route("api/customers", methods=["POST"])	except ValueError as e:

def create_customer(req: func.HttpRequest) -> func.HttpResponse:		logger.warning(f"Validation error: {e}")

	"""Create a new customer account."""		response = CustomerAccountResponse(

	try:			success=False,

		logger.info("Creating new customer")			message="Validation failed",

		body = req.get_json()			error=str(e),

				)

		# Validate input		return func.HttpResponse(

		customer_data = CustomerAccount(**body)			response.model_dump_json(),

					status_code=400,

		# Save to Cosmos DB			mimetype="application/json",

		cosmos_client = get_cosmos_client()		)

		cosmos_client.create_item(customer_data.model_dump())	except Exception as e:

				logger.error(f"Error creating customer: {e}")

		response = CustomerAccountResponse(		response = CustomerAccountResponse(

			success=True,			success=False,

			message="Customer created successfully",			message="Error creating customer account",

			data=customer_data			error=str(e),

		)		)

				return func.HttpResponse(

		return func.HttpResponse(			response.model_dump_json(),

			response.model_dump_json(),			status_code=500,

			status_code=201,			mimetype="application/json",

			mimetype="application/json"		)

		)

	except Exception as e:

		logger.error(f"Create customer error: {str(e)}")@app.route(route="customers/{customer_id}", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)

		return func.HttpResponse(def get_customer(req: func.HttpRequest) -> func.HttpResponse:

			json.dumps({"success": False, "error": str(e)}),	"""Fetch a customer account by ID.

			status_code=400,

			mimetype="application/json"	URL parameters:

		)		customer_id: The customer ID to retrieve

	"""

	try:

@app.route("api/customers/{id}", methods=["GET"])		customer_id = req.route_params.get("customer_id")

def get_customer(req: func.HttpRequest) -> func.HttpResponse:		if not customer_id:

	"""Get a customer by ID."""			raise ValueError("customer_id is required")

	try:

		customer_id = req.route_params.get("id")		cosmos = get_cosmos_client()

		logger.info(f"Getting customer: {customer_id}")		# Use customer_id as both ID and partition key

				result = cosmos.read_item(customer_id, partition_key=customer_id)

		cosmos_client = get_cosmos_client()

		item = cosmos_client.read_item(customer_id)		response = CustomerAccountResponse(

					success=True,

		if not item:			message="Customer account retrieved successfully",

			return func.HttpResponse(			data=result,

				json.dumps({"success": False, "error": "Customer not found"}),		)

				status_code=404,		return func.HttpResponse(

				mimetype="application/json"			response.model_dump_json(),

			)			status_code=200,

					mimetype="application/json",

		response = CustomerAccountResponse(		)

			success=True,

			message="Customer retrieved successfully",	except ValueError as e:

			data=CustomerAccount(**item)		logger.warning(f"Validation error: {e}")

		)		response = CustomerAccountResponse(

					success=False,

		return func.HttpResponse(			message="Customer not found",

			response.model_dump_json(),			error=str(e),

			status_code=200,		)

			mimetype="application/json"		return func.HttpResponse(

		)			response.model_dump_json(),

	except Exception as e:			status_code=404,

		logger.error(f"Get customer error: {str(e)}")			mimetype="application/json",

		return func.HttpResponse(		)

			json.dumps({"success": False, "error": str(e)}),	except Exception as e:

			status_code=500,		logger.error(f"Error retrieving customer: {e}")

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

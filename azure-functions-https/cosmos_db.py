"""Cosmos DB client initialization and operations."""
import os
import logging
from azure.cosmos import CosmosClient, PartitionKey, exceptions
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)


class CosmosDBClient:
	"""Wrapper for Cosmos DB operations with error handling."""

	def __init__(self):
		"""Initialize Cosmos DB client from environment variables."""
		self.endpoint = os.getenv("COSMOS_ENDPOINT")
		self.key = os.getenv("COSMOS_KEY")
		self.database_name = os.getenv("COSMOS_DATABASE", "CustomerDB")
		self.container_name = os.getenv("COSMOS_CONTAINER", "Accounts")

		if not self.endpoint or not self.key:
			raise ValueError("COSMOS_ENDPOINT and COSMOS_KEY environment variables are required")

		try:
			self.client = CosmosClient(self.endpoint, self.key)
			self.database = self.client.get_database_client(self.database_name)
			self.container = self.database.get_container_client(self.container_name)
			logger.info(f"Connected to Cosmos DB: {self.database_name}/{self.container_name}")
		except Exception as e:
			logger.error(f"Failed to initialize Cosmos DB client: {e}")
			raise

	def create_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
		"""Create a new item in Cosmos DB."""
		try:
			response = self.container.create_item(item)
			logger.info(f"Item created: {item.get('id')}")
			return response
		except exceptions.CosmosResourceExistsError:
			logger.warning(f"Item already exists: {item.get('id')}")
			raise ValueError(f"Customer with ID {item.get('id')} already exists")
		except Exception as e:
			logger.error(f"Error creating item: {e}")
			raise

	def read_item(self, item_id: str, partition_key: str) -> Dict[str, Any]:
		"""Read an item from Cosmos DB by ID."""
		try:
			response = self.container.read_item(item_id, partition_key=partition_key)
			logger.info(f"Item retrieved: {item_id}")
			return response
		except exceptions.CosmosResourceNotFoundError:
			logger.warning(f"Item not found: {item_id}")
			raise ValueError(f"Customer with ID {item_id} not found")
		except Exception as e:
			logger.error(f"Error reading item: {e}")
			raise

	def update_item(self, item_id: str, partition_key: str, item: Dict[str, Any]) -> Dict[str, Any]:
		"""Update an existing item in Cosmos DB."""
		try:
			# Ensure ID and partition key are set correctly
			item["id"] = item_id
			response = self.container.replace_item(item_id, item)
			logger.info(f"Item updated: {item_id}")
			return response
		except exceptions.CosmosResourceNotFoundError:
			logger.warning(f"Item not found for update: {item_id}")
			raise ValueError(f"Customer with ID {item_id} not found")
		except Exception as e:
			logger.error(f"Error updating item: {e}")
			raise

	def delete_item(self, item_id: str, partition_key: str) -> None:
		"""Delete an item from Cosmos DB."""
		try:
			self.container.delete_item(item_id, partition_key=partition_key)
			logger.info(f"Item deleted: {item_id}")
		except exceptions.CosmosResourceNotFoundError:
			logger.warning(f"Item not found for delete: {item_id}")
			raise ValueError(f"Customer with ID {item_id} not found")
		except Exception as e:
			logger.error(f"Error deleting item: {e}")
			raise

	def query_items(self, query: str, parameters: Optional[list] = None) -> list:
		"""Query items from Cosmos DB using SQL."""
		try:
			if parameters:
				response = self.container.query_items(query, parameters=parameters)
			else:
				response = self.container.query_items(query)
			items = list(response)
			logger.info(f"Query returned {len(items)} items")
			return items
		except Exception as e:
			logger.error(f"Error querying items: {e}")
			raise

	def close(self) -> None:
		"""Close the Cosmos DB client connection."""
		try:
			self.client.close()
			logger.info("Cosmos DB client closed")
		except Exception as e:
			logger.error(f"Error closing Cosmos DB client: {e}")

"""Data models for customer account operations."""
from typing import Optional
from pydantic import BaseModel, Field


class CustomerAccount(BaseModel):
	"""Customer account model with validation."""

	id: str = Field(..., description="Unique customer ID")
	name: str = Field(..., min_length=1, max_length=255, description="Customer full name")
	email: str = Field(..., description="Customer email address")
	phone: Optional[str] = Field(None, description="Customer phone number")
	account_type: str = Field(default="standard", description="Account type (standard, premium, enterprise)")
	status: str = Field(default="active", description="Account status (active, inactive, suspended)")
	balance: float = Field(default=0.0, description="Account balance")
	created_at: Optional[str] = None
	updated_at: Optional[str] = None

	class Config:
		json_schema_extra = {
			"example": {
				"id": "cust-001",
				"name": "John Doe",
				"email": "john@example.com",
				"phone": "+1-555-0123",
				"account_type": "premium",
				"status": "active",
				"balance": 5000.00,
			}
		}


class CustomerAccountResponse(BaseModel):
	"""Response model for customer operations."""

	success: bool
	message: str
	data: Optional[dict] = None
	error: Optional[str] = None

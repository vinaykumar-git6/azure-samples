from fastapi import FastAPI
from typing import List
from pydantic import BaseModel

app = FastAPI(title="Customer Mock API", version="1.0.0")


class Customer(BaseModel):
    id: int
    name: str
    email: str
    phone: str
    city: str
    status: str


CUSTOMERS: List[Customer] = [
    Customer(id=1, name="Ahmed Al Mansoori", email="ahmed.almansoori@example.com", phone="+971-50-1234567", city="Dubai", status="active"),
    Customer(id=2, name="Sara Al Rashidi",   email="sara.alrashidi@example.com",   phone="+971-52-2345678", city="Abu Dhabi", status="active"),
    Customer(id=3, name="Mohammed Al Farsi", email="mohammed.alfarsi@example.com", phone="+971-55-3456789", city="Sharjah", status="inactive"),
    Customer(id=4, name="Fatima Al Zaabi",   email="fatima.alzaabi@example.com",   phone="+971-56-4567890", city="Dubai", status="active"),
    Customer(id=5, name="Khalid Al Hamdan",  email="khalid.alhamdan@example.com",  phone="+971-50-5678901", city="Ajman", status="active"),
]


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/customers", response_model=List[Customer])
def get_customers():
    return CUSTOMERS


@app.get("/customers/{customer_id}", response_model=Customer)
def get_customer(customer_id: int):
    customer = next((c for c in CUSTOMERS if c.id == customer_id), None)
    if not customer:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Customer not found")
    return customer

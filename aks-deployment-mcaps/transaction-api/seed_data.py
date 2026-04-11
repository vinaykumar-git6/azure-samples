"""Seed MongoDB with dummy transaction data."""

from pymongo import MongoClient
from datetime import datetime, timedelta
import random
import os

MONGO_URI = os.getenv("MONGO_URI", "mongodb://admin:MongoP%40ss2026%21@localhost:27017")
DB_NAME = os.getenv("DB_NAME", "transactiondb")

DUMMY_TRANSACTIONS = [
    {"amount": 5000.00, "type": "credit", "description": "Salary deposit - January", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 1200.00, "type": "debit", "description": "Rent payment", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 85.50, "type": "debit", "description": "Electricity bill", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 250.00, "type": "credit", "description": "Freelance payment", "account": "ACC-1002", "currency": "USD", "status": "completed"},
    {"amount": 45.99, "type": "debit", "description": "Netflix subscription", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 3200.00, "type": "credit", "description": "Client invoice #INV-2024", "account": "ACC-1002", "currency": "USD", "status": "completed"},
    {"amount": 500.00, "type": "debit", "description": "Insurance premium", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 75.00, "type": "debit", "description": "Grocery shopping", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 10000.00, "type": "credit", "description": "Investment return", "account": "ACC-1003", "currency": "USD", "status": "completed"},
    {"amount": 299.99, "type": "debit", "description": "Annual cloud hosting", "account": "ACC-1002", "currency": "USD", "status": "completed"},
    {"amount": 150.00, "type": "credit", "description": "Refund - cancelled order", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 2000.00, "type": "debit", "description": "Wire transfer to vendor", "account": "ACC-1003", "currency": "AED", "status": "completed"},
    {"amount": 680.00, "type": "credit", "description": "Bonus payout", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 120.00, "type": "debit", "description": "Phone bill", "account": "ACC-1001", "currency": "USD", "status": "completed"},
    {"amount": 8500.00, "type": "credit", "description": "Contract payment - Q1", "account": "ACC-1002", "currency": "AED", "status": "completed"},
]


def seed():
    client = MongoClient(MONGO_URI)
    db = client[DB_NAME]
    col = db["transactions"]

    # Clear existing data
    deleted = col.delete_many({})
    print(f"Cleared {deleted.deleted_count} existing transactions")

    # Add timestamps spread over last 30 days
    now = datetime.utcnow()
    for i, txn in enumerate(DUMMY_TRANSACTIONS):
        txn["timestamp"] = (now - timedelta(days=random.randint(0, 30),
                                            hours=random.randint(0, 23),
                                            minutes=random.randint(0, 59))).isoformat() + "Z"

    result = col.insert_many(DUMMY_TRANSACTIONS)
    print(f"Inserted {len(result.inserted_ids)} dummy transactions")

    # Print summary
    for doc in col.find().limit(5):
        print(f"  {doc['type']:6s} | {doc['currency']} {doc['amount']:>10.2f} | {doc['description']}")
    print(f"  ... and {col.count_documents({}) - 5} more")

    client.close()


if __name__ == "__main__":
    seed()

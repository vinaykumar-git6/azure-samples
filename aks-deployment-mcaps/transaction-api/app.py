"""Transaction Management API - Simple CRUD with MongoDB."""

import os
import json
from datetime import datetime
from urllib.parse import quote_plus
from flask import Flask, request, jsonify
from pymongo import MongoClient
from bson import ObjectId, json_util

app = Flask(__name__)

# MongoDB connection - build URI with properly escaped credentials
MONGO_HOST = os.getenv("MONGO_HOST", "mongodb-svc")
MONGO_PORT = os.getenv("MONGO_PORT", "27017")
MONGO_USER = os.getenv("MONGO_USER", "admin")
MONGO_PASS = os.getenv("MONGO_PASS", "MongoP@ss2026!")
DB_NAME = os.getenv("DB_NAME", "transactiondb")

MONGO_URI = f"mongodb://{quote_plus(MONGO_USER)}:{quote_plus(MONGO_PASS)}@{MONGO_HOST}:{MONGO_PORT}"
print(f"Connecting to MongoDB at {MONGO_HOST}:{MONGO_PORT} as {MONGO_USER}")

client = MongoClient(MONGO_URI)
db = client[DB_NAME]
transactions = db["transactions"]


def serialize(doc):
    """Convert MongoDB document to JSON-serializable dict."""
    if doc is None:
        return None
    doc["_id"] = str(doc["_id"])
    return doc


# ──────────────────────────────────────────────
# Health check
# ──────────────────────────────────────────────
@app.route("/health", methods=["GET"])
def health():
    try:
        client.admin.command("ping")
        return jsonify({"status": "healthy", "database": "connected"}), 200
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 503


# ──────────────────────────────────────────────
# GET /api/transactions - List all transactions
# ──────────────────────────────────────────────
@app.route("/api/transactions", methods=["GET"])
def list_transactions():
    limit = request.args.get("limit", 100, type=int)
    skip = request.args.get("skip", 0, type=int)
    txn_type = request.args.get("type")

    query = {}
    if txn_type:
        query["type"] = txn_type

    results = list(transactions.find(query).skip(skip).limit(limit).sort("timestamp", -1))
    total = transactions.count_documents(query)

    return jsonify({
        "transactions": [serialize(t) for t in results],
        "total": total,
        "limit": limit,
        "skip": skip
    }), 200


# ──────────────────────────────────────────────
# GET /api/transactions/<id> - Get single transaction
# ──────────────────────────────────────────────
@app.route("/api/transactions/<txn_id>", methods=["GET"])
def get_transaction(txn_id):
    try:
        doc = transactions.find_one({"_id": ObjectId(txn_id)})
    except Exception:
        return jsonify({"error": "Invalid transaction ID"}), 400

    if not doc:
        return jsonify({"error": "Transaction not found"}), 404

    return jsonify(serialize(doc)), 200


# ──────────────────────────────────────────────
# POST /api/transactions - Create a transaction
# ──────────────────────────────────────────────
@app.route("/api/transactions", methods=["POST"])
def create_transaction():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body is required"}), 400

    required = ["amount", "type", "description"]
    missing = [f for f in required if f not in data]
    if missing:
        return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400

    txn = {
        "amount": float(data["amount"]),
        "type": data["type"],  # credit / debit
        "description": data["description"],
        "account": data.get("account", "default"),
        "currency": data.get("currency", "USD"),
        "status": data.get("status", "completed"),
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

    result = transactions.insert_one(txn)
    txn["_id"] = str(result.inserted_id)

    return jsonify(txn), 201


# ──────────────────────────────────────────────
# DELETE /api/transactions/<id>
# ──────────────────────────────────────────────
@app.route("/api/transactions/<txn_id>", methods=["DELETE"])
def delete_transaction(txn_id):
    try:
        result = transactions.delete_one({"_id": ObjectId(txn_id)})
    except Exception:
        return jsonify({"error": "Invalid transaction ID"}), 400

    if result.deleted_count == 0:
        return jsonify({"error": "Transaction not found"}), 404

    return jsonify({"message": "Transaction deleted"}), 200


# ──────────────────────────────────────────────
# GET /api/transactions/summary - Aggregation
# ──────────────────────────────────────────────
@app.route("/api/transactions/summary", methods=["GET"])
def transaction_summary():
    pipeline = [
        {"$group": {
            "_id": "$type",
            "total_amount": {"$sum": "$amount"},
            "count": {"$sum": 1},
            "avg_amount": {"$avg": "$amount"}
        }}
    ]
    results = list(transactions.aggregate(pipeline))
    summary = {}
    for r in results:
        summary[r["_id"]] = {
            "total_amount": round(r["total_amount"], 2),
            "count": r["count"],
            "avg_amount": round(r["avg_amount"], 2)
        }
    return jsonify(summary), 200


# ──────────────────────────────────────────────
# Run
# ──────────────────────────────────────────────
if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    # Use waitress in production
    try:
        from waitress import serve
        print(f"Starting transaction-api with waitress on port {port}")
        serve(app, host="0.0.0.0", port=port)
    except ImportError:
        print(f"Starting transaction-api with Flask dev server on port {port}")
        app.run(host="0.0.0.0", port=port, debug=True)

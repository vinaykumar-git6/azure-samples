import os
import requests
from flask import Flask, send_from_directory, request, jsonify, Response

app = Flask(__name__)

# customer-api backend URL (pod-to-pod via K8s service)
CUSTOMER_API = os.environ.get(
    "CUSTOMER_API_URL",
    "http://customer-api-service.dpworld.svc.cluster.local:80"
)


@app.route("/")
@app.route("/portal")
@app.route("/portal/")
def portal():
    return send_from_directory("public", "index.html")


@app.route("/health")
@app.route("/nginx-health")
def health():
    """Frontend own health check + proxy backend health."""
    try:
        r = requests.get(f"{CUSTOMER_API}/health", timeout=5)
        return r.json(), r.status_code
    except Exception:
        return {"status": "unhealthy", "service": "customer-frontend"}, 503


# --------------- Proxy all /api/* to customer-api (pod-to-pod) ---------------

@app.route("/api/customers", methods=["GET"])
def list_customers():
    r = requests.get(
        f"{CUSTOMER_API}/api/customers",
        params=request.args,
        timeout=10,
    )
    return Response(r.content, status=r.status_code, content_type=r.headers.get("Content-Type"))


@app.route("/api/customers/<int:customer_id>", methods=["GET"])
def get_customer(customer_id):
    r = requests.get(f"{CUSTOMER_API}/api/customers/{customer_id}", timeout=10)
    return Response(r.content, status=r.status_code, content_type=r.headers.get("Content-Type"))


@app.route("/api/customers", methods=["POST"])
def create_customer():
    r = requests.post(
        f"{CUSTOMER_API}/api/customers",
        json=request.get_json(silent=True),
        timeout=10,
    )
    return Response(r.content, status=r.status_code, content_type=r.headers.get("Content-Type"))


@app.route("/api/customers/<int:customer_id>", methods=["PUT"])
def update_customer(customer_id):
    r = requests.put(
        f"{CUSTOMER_API}/api/customers/{customer_id}",
        json=request.get_json(silent=True),
        timeout=10,
    )
    return Response(r.content, status=r.status_code, content_type=r.headers.get("Content-Type"))


@app.route("/api/customers/<int:customer_id>", methods=["DELETE"])
def delete_customer(customer_id):
    r = requests.delete(f"{CUSTOMER_API}/api/customers/{customer_id}", timeout=10)
    return Response(r.content, status=r.status_code, content_type=r.headers.get("Content-Type"))


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    from waitress import serve
    print(f"Customer Frontend running on port {port}")
    print(f"Proxying API calls to: {CUSTOMER_API}")
    serve(app, host="0.0.0.0", port=port)

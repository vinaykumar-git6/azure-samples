import os
import requests

CUSTOMER_API = os.environ.get("CUSTOMER_API_URL", "http://customer-api-service.dpworld.svc.cluster.local")

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Customer Portal - DP World</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    body {{ font-family: -apple-system, 'Segoe UI', sans-serif; background: #f0f2f5; color: #1a1a2e; }}
    .header {{
      background: linear-gradient(135deg, #0a1628 0%, #1a365d 50%, #2563eb 100%);
      color: white; padding: 20px 32px; box-shadow: 0 4px 20px rgba(0,0,0,0.15);
    }}
    .header-content {{ max-width: 1000px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; }}
    .header h1 {{ font-size: 22px; font-weight: 700; }}
    .header p {{ font-size: 13px; opacity: 0.7; margin-top: 2px; }}
    .status {{ display: flex; align-items: center; gap: 8px; font-size: 13px; padding: 6px 14px; background: rgba(255,255,255,0.1); border-radius: 20px; }}
    .dot {{ width: 8px; height: 8px; border-radius: 50%; display: inline-block; }}
    .dot.ok {{ background: #22c55e; box-shadow: 0 0 8px rgba(34,197,94,0.6); }}
    .dot.err {{ background: #ef4444; }}
    .main {{ max-width: 1000px; margin: 32px auto; padding: 0 24px; }}
    .card {{
      background: white; border-radius: 16px; overflow: hidden;
      box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 4px 16px rgba(0,0,0,0.04);
      border: 1px solid #e5e7eb; margin-bottom: 20px;
    }}
    .card-header {{ padding: 18px 24px; border-bottom: 1px solid #f3f4f6; font-size: 16px; font-weight: 700; color: #111827; }}
    .card-header span {{ font-size: 12px; color: #6b7280; font-weight: 400; margin-left: 8px; }}
    table {{ width: 100%; border-collapse: collapse; }}
    thead th {{ padding: 12px 20px; text-align: left; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: #6b7280; background: #f9fafb; border-bottom: 2px solid #e5e7eb; }}
    tbody td {{ padding: 14px 20px; font-size: 14px; border-bottom: 1px solid #f3f4f6; }}
    tbody tr:last-child td {{ border-bottom: none; }}
    tbody tr:hover {{ background: #f8faff; }}
    .name {{ font-weight: 600; color: #111827; }}
    .email {{ color: #6b7280; font-size: 13px; }}
    .badge {{ display: inline-block; padding: 3px 10px; border-radius: 6px; font-size: 12px; font-weight: 500; background: #eff6ff; color: #2563eb; }}
    .badge-green {{ background: #f0fdf4; color: #16a34a; }}
    .cust-card {{ padding: 20px 24px; border-bottom: 1px solid #f3f4f6; }}
    .cust-card:last-child {{ border-bottom: none; }}
    .cust-header {{ display: flex; align-items: center; gap: 14px; margin-bottom: 14px; }}
    .avatar {{ width: 48px; height: 48px; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 18px; font-weight: 700; color: white; background: linear-gradient(135deg, #2563eb, #7c3aed); }}
    .cust-header h3 {{ font-size: 16px; font-weight: 700; margin: 0; }}
    .cust-header p {{ font-size: 13px; color: #6b7280; margin: 2px 0 0; }}
    .detail-grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }}
    .detail-item label {{ font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #9ca3af; font-weight: 600; display: block; }}
    .detail-item p {{ font-size: 14px; font-weight: 500; color: #111827; margin-top: 3px; }}
    .error-box {{ text-align: center; padding: 40px; color: #dc2626; }}
  </style>
</head>
<body>
  <header class="header">
    <div class="header-content">
      <div>
        <h1>&#128100; Customer Portal</h1>
        <p>DP World &mdash; Top 5 Customers</p>
      </div>
      <div class="status">
        <span class="dot {health_class}"></span> {health_text}
      </div>
    </div>
  </header>
  <div class="main">
    {content}
  </div>
</body>
</html>"""

ROW_TEMPLATE = """<tr>
  <td><span class="badge">#{id}</span></td>
  <td><div class="name">{first_name} {last_name}</div><div class="email">{email}</div></td>
  <td>{phone}</td>
  <td>{city}</td>
  <td><span class="badge-green">{country}</span></td>
</tr>"""

DETAIL_TEMPLATE = """<div class="cust-card">
  <div class="cust-header">
    <div class="avatar">{initials}</div>
    <div><h3>{first_name} {last_name}</h3><p>{email}</p></div>
  </div>
  <div class="detail-grid">
    <div class="detail-item"><label>Customer ID</label><p>#{id}</p></div>
    <div class="detail-item"><label>Phone</label><p>{phone}</p></div>
    <div class="detail-item"><label>Address</label><p>{address}</p></div>
    <div class="detail-item"><label>City</label><p>{city}</p></div>
    <div class="detail-item"><label>Country</label><p>{country}</p></div>
    <div class="detail-item"><label>Created</label><p>{created_at}</p></div>
  </div>
</div>"""


def esc(val):
    """Escape HTML special characters."""
    if val is None:
        return "&mdash;"
    return str(val).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def fetch_customers():
    """Fetch top 5 customers from customer API."""
    try:
        resp = requests.get(f"{CUSTOMER_API}/api/customers", params={"page": 1, "limit": 5}, timeout=5)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        return {"error": str(e)}


def check_health():
    """Check customer API health."""
    try:
        resp = requests.get(f"{CUSTOMER_API}/health", timeout=3)
        data = resp.json()
        return data.get("status") == "healthy"
    except Exception:
        return False


def render_page():
    """Render the full HTML page with customer data."""
    healthy = check_health()
    health_class = "ok" if healthy else "err"
    health_text = "API Online" if healthy else "API Offline"

    data = fetch_customers()

    if "error" in data:
        content = f'<div class="card"><div class="error-box"><p>Failed to load customers: {esc(data["error"])}</p></div></div>'
    else:
        customers = data.get("customers", [])
        total = data.get("pagination", {}).get("total_items", len(customers))

        if not customers:
            content = '<div class="card"><div class="error-box"><p>No customers found.</p></div></div>'
        else:
            # Summary table
            rows = ""
            for c in customers:
                rows += ROW_TEMPLATE.format(
                    id=esc(c.get("id")),
                    first_name=esc(c.get("first_name")),
                    last_name=esc(c.get("last_name")),
                    email=esc(c.get("email")),
                    phone=esc(c.get("phone")),
                    city=esc(c.get("city")),
                    country=esc(c.get("country")),
                )

            content = f"""<div class="card">
<div class="card-header">Customer List<span>Showing top 5 of {total}</span></div>
<table>
<thead><tr><th>ID</th><th>Customer</th><th>Phone</th><th>City</th><th>Country</th></tr></thead>
<tbody>{rows}</tbody>
</table>
</div>"""

            # Detail cards
            content += '<div class="card"><div class="card-header">Customer Details</div>'
            for c in customers:
                initials = (c.get("first_name", "?")[0] + c.get("last_name", "?")[0]).upper()
                created = c.get("created_at", "—")
                if created and created != "—":
                    try:
                        from datetime import datetime
                        dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
                        created = dt.strftime("%d %b %Y")
                    except Exception:
                        pass
                content += DETAIL_TEMPLATE.format(
                    initials=esc(initials),
                    id=esc(c.get("id")),
                    first_name=esc(c.get("first_name")),
                    last_name=esc(c.get("last_name")),
                    email=esc(c.get("email")),
                    phone=esc(c.get("phone")),
                    address=esc(c.get("address")),
                    city=esc(c.get("city")),
                    country=esc(c.get("country")),
                    created_at=created,
                )
            content += "</div>"

    return HTML_TEMPLATE.format(
        health_class=health_class,
        health_text=health_text,
        content=content,
    )


# --- Flask app ---
from flask import Flask

app = Flask(__name__)


@app.route("/")
@app.route("/portal")
@app.route("/portal/")
def portal():
    return render_page(), 200, {"Content-Type": "text/html"}


@app.route("/health")
@app.route("/nginx-health")
def health():
    return {"status": "healthy", "service": "customer-frontend"}, 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    from waitress import serve
    print(f"Customer Frontend running on port {port}")
    serve(app, host="0.0.0.0", port=port)

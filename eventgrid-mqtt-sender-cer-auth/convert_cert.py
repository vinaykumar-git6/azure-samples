"""Convert PFX certificate to PEM format for MQTT client"""
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import getpass

# Read PFX file
pfx_path = "client-cert.pfx"
pem_cert_path = "client-cert.pem"
pem_key_path = "client-key.pem"

# Get password
password = "temp123"

# Load PFX
with open(pfx_path, "rb") as f:
    pfx_data = f.read()

# Parse PFX
from cryptography.hazmat.primitives.serialization import pkcs12
private_key, certificate, additional_certificates = pkcs12.load_key_and_certificates(
    pfx_data,
    password.encode(),
    backend=default_backend()
)

# Export certificate
cert_pem = certificate.public_bytes(serialization.Encoding.PEM)
with open(pem_cert_path, "wb") as f:
    f.write(cert_pem)
print(f"✅ Certificate exported to {pem_cert_path}")

# Export private key
key_pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.TraditionalOpenSSL,
    encryption_algorithm=serialization.NoEncryption()
)
with open(pem_key_path, "wb") as f:
    f.write(key_pem)
print(f"✅ Private key exported to {pem_key_path}")

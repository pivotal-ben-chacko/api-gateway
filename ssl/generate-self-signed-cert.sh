#!/bin/bash
# Generate self-signed SSL certificates for the NGINX API Gateway
# For production use, replace with proper CA-signed certificates

set -e

echo "Generating self-signed SSL certificate for NGINX API Gateway..."

# Generate private key
openssl genrsa -out gateway.key 2048

# Generate certificate signing request
openssl req -new -key gateway.key -out gateway.csr \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=bosh-api-gateway"

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -days 365 -in gateway.csr -signkey gateway.key -out gateway.crt

# Set appropriate permissions
chmod 600 gateway.key
chmod 644 gateway.crt

# Clean up CSR
rm gateway.csr

echo "Certificate generation complete!"
echo "Generated files:"
echo "  - gateway.key (private key)"
echo "  - gateway.crt (certificate)"
echo ""
echo "IMPORTANT: For production use, replace these with proper CA-signed certificates"

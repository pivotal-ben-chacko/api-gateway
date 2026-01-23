# SSL Certificates

This directory contains SSL certificates for the NGINX API Gateway.

## Required Certificates

### 1. Gateway Certificates (Client-facing)
These certificates are used for the connection FROM Bosh Director TO NGINX:
- `gateway.crt` - SSL certificate for the gateway
- `gateway.key` - Private key for the gateway

### 2. vCenter CA Certificate (Optional but Recommended)
For secure backend connections TO vCenter:
- `vcenter-ca.crt` - vCenter's CA certificate for SSL verification

## Generating Self-Signed Certificates (Development/Testing)

Run the provided script:
```bash
cd ssl
./generate-self-signed-cert.sh
```

## Production Certificates

For production use:
1. Obtain proper CA-signed certificates from your certificate authority
2. Place the certificate and key in this directory
3. Update the paths in `conf.d/vcenter-proxy.conf`:
   ```nginx
   ssl_certificate /etc/nginx/ssl/gateway.crt;
   ssl_certificate_key /etc/nginx/ssl/gateway.key;
   ```

## vCenter SSL Verification

To enable SSL verification for the vCenter backend connection:

1. Export vCenter's CA certificate:
   - Log into vCenter
   - Download the CA certificate from: `https://your-vcenter/certs/download.zip`
   - Extract and convert to PEM format if needed

2. Place the certificate as `vcenter-ca.crt` in this directory

3. Update `conf.d/vcenter-proxy.conf`:
   ```nginx
   proxy_ssl_verify on;
   proxy_ssl_trusted_certificate /etc/nginx/ssl/vcenter-ca.crt;
   ```

## Security Notes

- Keep private keys secure with `chmod 600 *.key`
- Never commit private keys to version control
- Rotate certificates before expiration
- Use strong key sizes (2048-bit minimum, 4096-bit recommended)

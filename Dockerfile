FROM nginx:1.27-alpine

# Install OpenSSL for certificate generation
RUN apk add --no-cache openssl

# Create directories
RUN mkdir -p /etc/nginx/ssl /etc/nginx/conf.d /var/log/nginx

# Copy configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/vcenter-proxy.conf /etc/nginx/conf.d/vcenter-proxy.conf
COPY ssl/generate-self-signed-cert.sh /etc/nginx/ssl/generate-self-signed-cert.sh

# Make script executable
RUN chmod +x /etc/nginx/ssl/generate-self-signed-cert.sh

# Generate self-signed certificates if they don't exist
# For production, mount proper certificates as volumes
RUN cd /etc/nginx/ssl && \
    if [ ! -f gateway.crt ]; then \
        ./generate-self-signed-cert.sh; \
    fi

# Set proper permissions
RUN chmod 600 /etc/nginx/ssl/*.key 2>/dev/null || true && \
    chmod 644 /etc/nginx/ssl/*.crt 2>/dev/null || true

# Expose HTTPS port
EXPOSE 443 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider --no-check-certificate https://localhost/nginx-health || exit 1

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]

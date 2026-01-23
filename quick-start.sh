#!/bin/bash
# Quick start script for NGINX API Gateway

set -e

echo "=========================================="
echo "NGINX API Gateway - Quick Start"
echo "=========================================="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed. Please install docker-compose first."
    exit 1
fi

# Create logs directory
echo "Creating logs directory..."
mkdir -p logs

# Check if vCenter host is configured
if grep -q "VCENTER_HOST:443" conf.d/vcenter-proxy.conf; then
    echo ""
    echo "WARNING: vCenter host is not configured!"
    echo "Please edit conf.d/vcenter-proxy.conf and replace 'VCENTER_HOST' with your actual vCenter hostname or IP."
    echo ""
    read -p "Have you configured the vCenter host? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please configure the vCenter host and run this script again."
        exit 1
    fi
fi

# Generate SSL certificates if they don't exist
if [ ! -f ssl/gateway.crt ]; then
    echo ""
    echo "Generating self-signed SSL certificates..."
    cd ssl
    ./generate-self-signed-cert.sh
    cd ..
    echo ""
    echo "WARNING: Using self-signed certificates. For production, use proper CA-signed certificates."
else
    echo "SSL certificates found."
fi

echo ""
echo "Building and starting the NGINX API Gateway..."
docker-compose up -d --build

echo ""
echo "=========================================="
echo "Gateway is starting..."
echo "=========================================="
echo ""
echo "Checking health status..."
sleep 5

# Check health
if docker-compose ps | grep -q "Up"; then
    echo "✓ Container is running"

    # Try health check
    if curl -k -s https://localhost/nginx-health > /dev/null 2>&1; then
        echo "✓ Health check passed"
    else
        echo "⚠ Health check failed - gateway may still be starting"
    fi
else
    echo "✗ Container failed to start"
    echo "Check logs with: docker-compose logs"
    exit 1
fi

echo ""
echo "=========================================="
echo "Gateway is ready!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Update your Bosh Director configuration to point to this gateway"
echo "2. Monitor logs: docker-compose logs -f"
echo "3. View access logs: tail -f logs/vcenter-access.log"
echo "4. Check health: curl -k https://localhost/nginx-health"
echo ""
echo "To stop: docker-compose down"
echo ""

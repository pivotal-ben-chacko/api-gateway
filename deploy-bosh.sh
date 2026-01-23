#!/bin/bash
# BOSH Deployment Script for vCenter API Gateway

set -e

DEPLOYMENT_NAME="vcenter-gateway"
MANIFEST_FILE="nginx.yml"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "BOSH Deployment: vCenter API Gateway"
echo "=========================================="
echo ""

# Check if bosh CLI is installed
if ! command -v bosh &> /dev/null; then
    echo -e "${RED}Error: BOSH CLI is not installed${NC}"
    echo "Please install BOSH CLI: https://bosh.io/docs/cli-v2-install/"
    exit 1
fi

# Check if logged into BOSH Director
if ! bosh env &> /dev/null; then
    echo -e "${RED}Error: Not logged into BOSH Director${NC}"
    echo "Please run: bosh login"
    exit 1
fi

echo -e "${GREEN}✓ BOSH CLI found and logged in${NC}"
echo ""

# Check if manifest file exists
if [ ! -f "$MANIFEST_FILE" ]; then
    echo -e "${RED}Error: Manifest file '$MANIFEST_FILE' not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Manifest file found${NC}"
echo ""

# Check if vCenter host is configured
if grep -q "VCENTER_HOST_PLACEHOLDER" "$MANIFEST_FILE"; then
    echo -e "${YELLOW}WARNING: vCenter host is not configured!${NC}"
    echo ""
    echo "Please edit nginx.yml and update the vcenter_host property:"
    echo "  vcenter_host: \"your-vcenter.example.com\""
    echo ""
    read -p "Have you configured the vCenter host? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please configure the vCenter host and run this script again."
        exit 1
    fi
fi

# Prompt for deployment variables
echo "Deployment Configuration:"
echo "------------------------"

# Check if variables file exists
if [ -f "vars.yml" ]; then
    echo -e "${GREEN}Found vars.yml file${NC}"
    read -p "Use existing vars.yml? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        USE_VARS_FILE=false
    else
        USE_VARS_FILE=true
    fi
else
    USE_VARS_FILE=false
fi

# Build deployment command
DEPLOY_CMD="bosh -d $DEPLOYMENT_NAME deploy $MANIFEST_FILE"

if [ "$USE_VARS_FILE" = true ]; then
    DEPLOY_CMD="$DEPLOY_CMD -l vars.yml"
else
    # Prompt for key variables
    read -p "Enter vCenter hostname/IP (or press Enter to use value from manifest): " VCENTER_HOST
    read -p "Enter availability zone name (default: AZ1): " AZ_NAME
    AZ_NAME=${AZ_NAME:-AZ1}
    read -p "Enter network name (default: Infra): " NETWORK_NAME
    NETWORK_NAME=${NETWORK_NAME:-Infra}

    if [ ! -z "$VCENTER_HOST" ]; then
        DEPLOY_CMD="$DEPLOY_CMD -v vcenter_host=$VCENTER_HOST"
    fi
fi

echo ""
echo "Deployment Command:"
echo "$DEPLOY_CMD"
echo ""
read -p "Proceed with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "=========================================="
echo "Starting Deployment..."
echo "=========================================="
echo ""

# Execute deployment
eval $DEPLOY_CMD

DEPLOY_STATUS=$?

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo -e "${GREEN}Deployment Successful!${NC}"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Get the gateway IP:"
    echo "   bosh -d $DEPLOYMENT_NAME instances"
    echo ""
    echo "2. Test the health endpoint:"
    echo "   curl -k https://GATEWAY_IP/nginx-health"
    echo ""
    echo "3. View logs:"
    echo "   bosh -d $DEPLOYMENT_NAME logs -f"
    echo ""
    echo "4. SSH to the instance:"
    echo "   bosh -d $DEPLOYMENT_NAME ssh nginx/0"
    echo ""
    echo "5. Update your Bosh Director configuration:"
    echo "   Point the vCenter host in your CPI config to the gateway IP"
    echo ""

    # Try to get the instance IP
    echo "Fetching gateway IP address..."
    bosh -d $DEPLOYMENT_NAME instances --column=ips | grep -v "^IPs$" | head -1
else
    echo ""
    echo "=========================================="
    echo -e "${RED}Deployment Failed!${NC}"
    echo "=========================================="
    echo ""
    echo "Troubleshooting:"
    echo "1. Check the task output:"
    echo "   bosh tasks --recent=5"
    echo ""
    echo "2. View detailed logs:"
    echo "   bosh -d $DEPLOYMENT_NAME logs"
    echo ""
    echo "3. Check instance status:"
    echo "   bosh -d $DEPLOYMENT_NAME instances --ps"
    exit 1
fi

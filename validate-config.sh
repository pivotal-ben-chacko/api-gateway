#!/bin/bash
# Configuration Validation Script for NGINX API Gateway

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "NGINX Configuration Validator"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

# Check if nginx.yml exists
echo "Checking BOSH manifest..."
if [ -f "nginx.yml" ]; then
    echo -e "${GREEN}✓ nginx.yml found${NC}"

    # Check if vCenter host is configured
    if grep -q "VCENTER_HOST_PLACEHOLDER" nginx.yml; then
        echo -e "${RED}✗ vCenter host not configured in nginx.yml${NC}"
        echo "  Please update the vcenter_host property with your actual vCenter hostname/IP"
        ERRORS=$((ERRORS+1))
    else
        VCENTER_HOST=$(grep "vcenter_host:" nginx.yml | head -1 | awk '{print $2}' | tr -d '"')
        echo -e "${GREEN}✓ vCenter host configured: $VCENTER_HOST${NC}"
    fi
else
    echo -e "${YELLOW}⚠ nginx.yml not found (not required for Docker deployment)${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""
echo "Checking NGINX configuration files..."

# Check nginx.conf
if [ -f "nginx.conf" ]; then
    echo -e "${GREEN}✓ nginx.conf found${NC}"
else
    echo -e "${RED}✗ nginx.conf not found${NC}"
    ERRORS=$((ERRORS+1))
fi

# Check vcenter-proxy.conf
if [ -f "conf.d/vcenter-proxy.conf" ]; then
    echo -e "${GREEN}✓ conf.d/vcenter-proxy.conf found${NC}"

    # Check if vCenter host is configured in standalone config
    if grep -q "server VCENTER_HOST:443" conf.d/vcenter-proxy.conf; then
        echo -e "${YELLOW}⚠ vCenter host not configured in conf.d/vcenter-proxy.conf${NC}"
        echo "  This is OK for BOSH deployment, but required for Docker/manual deployment"
        WARNINGS=$((WARNINGS+1))
    else
        echo -e "${GREEN}✓ vCenter host appears to be configured in proxy config${NC}"
    fi
else
    echo -e "${RED}✗ conf.d/vcenter-proxy.conf not found${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""
echo "Checking SSL configuration..."

# Check SSL directory
if [ -d "ssl" ]; then
    echo -e "${GREEN}✓ ssl directory found${NC}"

    if [ -f "ssl/generate-self-signed-cert.sh" ]; then
        echo -e "${GREEN}✓ Certificate generation script found${NC}"

        # Check if script is executable
        if [ -x "ssl/generate-self-signed-cert.sh" ]; then
            echo -e "${GREEN}✓ Certificate script is executable${NC}"
        else
            echo -e "${YELLOW}⚠ Certificate script is not executable${NC}"
            echo "  Run: chmod +x ssl/generate-self-signed-cert.sh"
            WARNINGS=$((WARNINGS+1))
        fi
    else
        echo -e "${RED}✗ Certificate generation script not found${NC}"
        ERRORS=$((ERRORS+1))
    fi

    # Check if certificates already exist
    if [ -f "ssl/gateway.crt" ] && [ -f "ssl/gateway.key" ]; then
        echo -e "${GREEN}✓ SSL certificates already generated${NC}"

        # Check certificate expiration
        EXPIRY=$(openssl x509 -in ssl/gateway.crt -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ ! -z "$EXPIRY" ]; then
            echo "  Certificate expires: $EXPIRY"
        fi
    else
        echo -e "${YELLOW}⚠ SSL certificates not yet generated${NC}"
        echo "  Certificates will be auto-generated on first deployment"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${RED}✗ ssl directory not found${NC}"
    ERRORS=$((ERRORS+1))
fi

echo ""
echo "Checking Docker configuration..."

if [ -f "Dockerfile" ]; then
    echo -e "${GREEN}✓ Dockerfile found${NC}"
else
    echo -e "${YELLOW}⚠ Dockerfile not found${NC}"
    WARNINGS=$((WARNINGS+1))
fi

if [ -f "docker-compose.yml" ]; then
    echo -e "${GREEN}✓ docker-compose.yml found${NC}"
else
    echo -e "${YELLOW}⚠ docker-compose.yml not found${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""
echo "Checking deployment scripts..."

if [ -f "deploy-bosh.sh" ]; then
    echo -e "${GREEN}✓ BOSH deployment script found${NC}"
    if [ ! -x "deploy-bosh.sh" ]; then
        echo -e "${YELLOW}⚠ deploy-bosh.sh is not executable${NC}"
        echo "  Run: chmod +x deploy-bosh.sh"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${YELLOW}⚠ deploy-bosh.sh not found${NC}"
    WARNINGS=$((WARNINGS+1))
fi

if [ -f "quick-start.sh" ]; then
    echo -e "${GREEN}✓ Docker quick-start script found${NC}"
    if [ ! -x "quick-start.sh" ]; then
        echo -e "${YELLOW}⚠ quick-start.sh is not executable${NC}"
        echo "  Run: chmod +x quick-start.sh"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${YELLOW}⚠ quick-start.sh not found${NC}"
    WARNINGS=$((WARNINGS+1))
fi

echo ""
echo "Checking documentation..."

if [ -f "README.md" ]; then
    echo -e "${GREEN}✓ README.md found${NC}"
else
    echo -e "${YELLOW}⚠ README.md not found${NC}"
    WARNINGS=$((WARNINGS+1))
fi

if [ -f "BOSH-DEPLOYMENT.md" ]; then
    echo -e "${GREEN}✓ BOSH-DEPLOYMENT.md found${NC}"
else
    echo -e "${YELLOW}⚠ BOSH-DEPLOYMENT.md not found${NC}"
    WARNINGS=$((WARNINGS+1))
fi

# Test NGINX configuration syntax if nginx is installed
echo ""
echo "Testing NGINX configuration syntax..."

if command -v nginx &> /dev/null; then
    echo "NGINX is installed, testing configuration..."

    # Create temporary directory for testing
    TEMP_DIR=$(mktemp -d)
    cp nginx.conf "$TEMP_DIR/"
    mkdir -p "$TEMP_DIR/conf.d"
    cp conf.d/vcenter-proxy.conf "$TEMP_DIR/conf.d/"

    # Replace BOSH-specific syntax for testing
    sed -i.bak 's/((vcenter_host))/vcenter.example.com/g' "$TEMP_DIR/conf.d/vcenter-proxy.conf" 2>/dev/null || \
        sed -i '' 's/((vcenter_host))/vcenter.example.com/g' "$TEMP_DIR/conf.d/vcenter-proxy.conf"

    # Create dummy SSL files for syntax check
    mkdir -p "$TEMP_DIR/ssl"
    touch "$TEMP_DIR/ssl/gateway.crt"
    touch "$TEMP_DIR/ssl/gateway.key"

    # Update paths in test config
    sed -i.bak "s|/etc/nginx/ssl|$TEMP_DIR/ssl|g" "$TEMP_DIR/conf.d/vcenter-proxy.conf" 2>/dev/null || \
        sed -i '' "s|/etc/nginx/ssl|$TEMP_DIR/ssl|g" "$TEMP_DIR/conf.d/vcenter-proxy.conf"

    # Note: Full syntax check would require proper NGINX environment
    echo -e "${YELLOW}⚠ Full NGINX syntax validation requires proper deployment environment${NC}"
    echo "  Manual check: sudo nginx -t (after deployment)"

    # Cleanup
    rm -rf "$TEMP_DIR"
else
    echo -e "${YELLOW}⚠ NGINX not installed locally, skipping syntax check${NC}"
    echo "  Configuration syntax will be validated during deployment"
fi

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Configuration is ready for deployment.${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found, but configuration should work.${NC}"
    echo ""
    echo "You can proceed with deployment, but consider addressing the warnings above."
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found.${NC}"
    echo ""
    echo "Please fix the errors above before deploying."
    exit 1
fi

# BOSH Deployment Guide for vCenter API Gateway

This guide covers deploying the NGINX API Gateway for Bosh Director CPI to vCenter using BOSH.

## Prerequisites

- BOSH CLI installed and configured
- Access to a BOSH Director
- NGINX BOSH release available (version 1.21.6 or later)
- Network connectivity from the deployment network to vCenter
- Cloud Foundry environment (if deploying to CF)

## Deployment Manifest

The `nginx.yml` manifest file contains a complete BOSH deployment configuration for the vCenter API Gateway.

## Configuration Steps

### 1. Update vCenter Host

Edit `nginx.yml` and replace the vCenter host placeholder:

```yaml
properties:
  vcenter_host: "vcenter.example.com"  # Replace with your actual vCenter hostname or IP
```

**Important**: The vCenter host is used in two places in the configuration:
1. In the `vcenter_host` property (line 27)
2. It's automatically substituted into the NGINX config using `((vcenter_host))` template syntax

### 2. Review and Adjust Instance Configuration

Check the instance configuration matches your environment:

```yaml
instance_groups:
- name: nginx
  azs: [AZ1]              # Update with your availability zone
  instances: 1            # Number of gateway instances
  vm_type: medium.mem     # Adjust based on expected traffic
  networks:
  - name: Infra           # Update with your network name
```

### 3. Update Network Configuration

Update the network name to match your BOSH environment:

```yaml
networks:
- name: Infra  # Change to your network name (e.g., default, private, etc.)
```

### 4. (Optional) Adjust Resource Allocation

For high-traffic environments, consider increasing:

```yaml
vm_type: large.mem  # or large.cpu, depending on your needs
instances: 2         # for high availability
```

## SSL Certificates

### Self-Signed Certificates (Development/Testing)

The deployment automatically generates self-signed SSL certificates during the `pre_start` script. No additional configuration needed.

### Production Certificates (Recommended)

To use production CA-signed certificates:

1. **Add certificates to the manifest**:

```yaml
properties:
  vcenter_host: "vcenter.example.com"

  ssl_certificate: |
    -----BEGIN CERTIFICATE-----
    [Your certificate content]
    -----END CERTIFICATE-----

  ssl_key: |
    -----BEGIN PRIVATE KEY-----
    [Your private key content]
    -----END PRIVATE KEY-----
```

2. **Update the pre_start script** to use these certificates:

```bash
pre_start: |
  #!/bin/bash -ex
  SSL_DIR=/var/vcap/jobs/nginx/etc/ssl
  mkdir -p $SSL_DIR

  # Write certificates from manifest properties
  cat > $SSL_DIR/gateway.crt <<EOF
  ${ssl_certificate}
  EOF

  cat > $SSL_DIR/gateway.key <<EOF
  ${ssl_key}
  EOF

  chmod 600 $SSL_DIR/gateway.key
  chmod 644 $SSL_DIR/gateway.crt
  chown -R vcap:vcap $SSL_DIR
```

## Deployment Commands

### Upload NGINX Release (if not already uploaded)

```bash
# Upload from bosh.io
bosh upload-release https://bosh.io/d/github.com/cloudfoundry-community/nginx-release

# Or from local file
bosh upload-release /path/to/nginx-release.tgz
```

### Deploy the Gateway

```bash
# Deploy with default manifest
bosh -d vcenter-gateway deploy nginx.yml

# Deploy with custom variables
bosh -d vcenter-gateway deploy nginx.yml \
  -v vcenter_host=vcenter.example.com \
  -v az_name=AZ1 \
  -v network_name=Infra
```

### Using Variables File

Create a `vars.yml` file:

```yaml
vcenter_host: vcenter.example.com
az_name: AZ1
network_name: Infra
vm_type: medium.mem
instances: 1
```

Deploy with variables:

```bash
bosh -d vcenter-gateway deploy nginx.yml -l vars.yml
```

### Using BOSH CLI Interpolation

Make the manifest more flexible with BOSH variables:

```yaml
properties:
  vcenter_host: ((vcenter_host))
```

Then deploy with:

```bash
bosh -d vcenter-gateway deploy nginx.yml -v vcenter_host=vcenter.example.com
```

## Post-Deployment Configuration

### 1. Get Gateway IP Address

```bash
bosh -d vcenter-gateway instances
```

Example output:
```
Instance                                    Process State  AZ   IPs
nginx/a1b2c3d4-e5f6-7890-abcd-ef1234567890  running        AZ1  10.0.1.100
```

### 2. Verify Gateway Health

```bash
# From a machine with access to the gateway
curl -k https://10.0.1.100/nginx-health
```

Expected output: `healthy`

### 3. Test vCenter Connectivity

```bash
# Test that the gateway can reach vCenter
curl -k -v https://10.0.1.100/api
```

Should return a vCenter API response (or authentication error if not authenticated).

### 4. View Logs

```bash
# Stream logs from the gateway
bosh -d vcenter-gateway logs -f

# Download logs
bosh -d vcenter-gateway logs

# SSH to the instance
bosh -d vcenter-gateway ssh nginx/0
sudo su -
tail -f /var/vcap/sys/log/nginx/vcenter-access.log
```

## Configure Bosh Director

Update your Bosh Director's CPI configuration to use the gateway.

### For vSphere CPI

Edit your Bosh Director manifest or cloud config:

```yaml
vcenter:
  host: 10.0.1.100  # Gateway IP address, not direct vCenter
  user: administrator@vsphere.local
  password: ((vcenter_password))
  datacenters:
    - name: ((vcenter_datacenter))
      # ... rest of configuration
```

### For Cloud Config

```bash
bosh update-cloud-config cloud-config.yml -v vcenter_host=10.0.1.100
```

## Monitoring and Troubleshooting

### Check Deployment Status

```bash
bosh -d vcenter-gateway instances --ps
bosh -d vcenter-gateway vms --vitals
```

### View Access Logs

```bash
bosh -d vcenter-gateway ssh nginx/0
sudo tail -f /var/vcap/sys/log/nginx/vcenter-access.log
```

Log format includes:
- Client IP
- Request details
- Response status and size
- Timing metrics (request time, upstream connect/header/response time)

### View Error Logs

```bash
bosh -d vcenter-gateway ssh nginx/0
sudo tail -f /var/vcap/sys/log/nginx/vcenter-error.log
```

### Common Issues

#### 1. Deployment Fails

Check BOSH task output:
```bash
bosh -d vcenter-gateway task [task-id] --debug
```

#### 2. Gateway Not Reachable

- Verify security groups allow traffic on port 443
- Check network configuration in manifest
- Verify VM is running: `bosh -d vcenter-gateway instances`

#### 3. Cannot Connect to vCenter

- SSH to the gateway and test connectivity:
  ```bash
  bosh -d vcenter-gateway ssh nginx/0
  curl -k https://YOUR_VCENTER_HOST
  ```
- Check DNS resolution: `nslookup YOUR_VCENTER_HOST`
- Verify firewall rules allow outbound 443 from gateway to vCenter

#### 4. SSL Certificate Errors

- Check certificate generation in pre_start logs:
  ```bash
  bosh -d vcenter-gateway ssh nginx/0
  sudo cat /var/vcap/sys/log/nginx/pre-start.stdout.log
  ```
- Verify certificate files exist and have correct permissions:
  ```bash
  sudo ls -l /var/vcap/jobs/nginx/etc/ssl/
  ```

#### 5. Bosh Director Cannot Connect to Gateway

- Verify Bosh Director can reach gateway IP
- Check if gateway is listening on 443:
  ```bash
  bosh -d vcenter-gateway ssh nginx/0
  sudo netstat -tlnp | grep :443
  ```
- Test from Bosh Director host:
  ```bash
  curl -k https://GATEWAY_IP/nginx-health
  ```

## Scaling and High Availability

### Scale Up Instances

Edit `nginx.yml`:

```yaml
instance_groups:
- name: nginx
  instances: 2  # Increase number of instances
```

Redeploy:
```bash
bosh -d vcenter-gateway deploy nginx.yml
```

### Add Load Balancer

For multiple instances, add a load balancer in front:

1. Deploy multiple gateway instances
2. Configure external load balancer to distribute traffic across all instances
3. Point Bosh Director to load balancer IP instead of individual gateway IPs

### Update Strategy

The manifest includes a safe update strategy:

```yaml
update:
  canaries: 2              # Update 2 instances first
  max_in_flight: 1         # Update 1 at a time after canaries
  canary_watch_time: 5000-60000
  update_watch_time: 5000-60000
```

This ensures:
- Canary instances are updated first and monitored
- Rolling updates prevent downtime (if using multiple instances)
- Automatic rollback if canary instances fail

## Updating the Deployment

### Update Configuration

1. Edit `nginx.yml` with your changes
2. Deploy the update:
   ```bash
   bosh -d vcenter-gateway deploy nginx.yml
   ```

### Update NGINX Release

```bash
# Upload new release
bosh upload-release https://bosh.io/d/github.com/cloudfoundry-community/nginx-release?v=1.25.0

# Update version in nginx.yml
releases:
- name: nginx
  version: 1.25.0

# Deploy
bosh -d vcenter-gateway deploy nginx.yml
```

### Recreate VMs

Force recreation of all VMs:
```bash
bosh -d vcenter-gateway recreate
```

## Removing the Deployment

### Delete Deployment

```bash
bosh -d vcenter-gateway delete-deployment
```

### Cleanup

```bash
# Remove orphaned disks if any
bosh clean-up --all
```

## Security Hardening

### Production Recommendations

1. **Use CA-signed certificates** instead of self-signed
2. **Enable vCenter SSL verification**:
   - Add vCenter CA certificate to deployment
   - Set `proxy_ssl_verify on;` in nginx_conf
3. **Restrict access** with firewall rules or NGINX allow/deny directives
4. **Enable mutual TLS** if Bosh supports it
5. **Regular certificate rotation**
6. **Monitor logs** for suspicious activity
7. **Enable rate limiting** for additional protection

### Add IP Allowlist

Edit `nginx.yml` and add to server block:

```nginx
server {
  listen 443 ssl http2;

  # Allow only Bosh Director IPs
  allow 10.0.1.0/24;    # Bosh Director network
  deny all;

  # ... rest of configuration
}
```

## Advanced Configuration

### Enable Debug Logging

For troubleshooting, enable debug logging:

```yaml
nginx_conf: |
  error_log /var/vcap/sys/log/nginx/error.log debug;
```

**Warning**: Debug logging is very verbose. Disable after troubleshooting.

### Custom Timeout Values

Adjust timeouts for your environment:

```nginx
location / {
  proxy_connect_timeout 120s;  # Increase if vCenter is slow to connect
  proxy_send_timeout 600s;     # Increase for large uploads
  proxy_read_timeout 600s;     # Increase for long-running operations
}
```

### Add Custom Headers

```nginx
location / {
  proxy_set_header X-Gateway-Version "1.0";
  proxy_set_header X-Forwarded-Gateway "bosh-vcenter-gateway";
  # ... other headers
}
```

## Support and Troubleshooting

For issues:
1. Check BOSH logs: `bosh -d vcenter-gateway logs`
2. Check NGINX logs on the VM
3. Verify network connectivity
4. Test with curl from different network locations
5. Review Bosh Director logs for CPI errors

## References

- [NGINX BOSH Release](https://github.com/cloudfoundry-community/nginx-release)
- [BOSH Documentation](https://bosh.io/docs/)
- [vCenter API Documentation](https://developer.vmware.com/apis/vsphere-automation/)

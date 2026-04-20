# NGINX API Gateway for Bosh Director CPI to vCenter

This NGINX configuration provides an API gateway to proxy all Bosh Director Cloud Provider Interface (CPI) calls to vCenter. It enables centralized logging, monitoring, and control of vCenter API traffic.

## Features

- **SSL Termination**: Terminates SSL from Bosh Director and establishes new SSL connections to vCenter
- **Detailed Logging**: Comprehensive request/response logging with timing information
- **Request Buffering**: Handles large API requests and responses efficiently
- **Connection Pooling**: Maintains keepalive connections to vCenter for better performance
- **Health Checks**: Built-in health check endpoint for monitoring
- **API Endpoint Routing**: Specific handling for vCenter SOAP, REST, and vAPI endpoints

## Architecture

```
Bosh Director CPI → NGINX Gateway (port 443) → vCenter (port 443)
                         ↓
                   Detailed Logs
```

## Deployment Options

This gateway can be deployed in multiple ways:

1. **BOSH Deployment** (Recommended for production)
   - Managed by BOSH Director
   - Auto-healing and updates
   - See [BOSH-DEPLOYMENT.md](BOSH-DEPLOYMENT.md) for detailed instructions
   - Quick start: `./deploy-bosh.sh`

2. **Docker Deployment** (Development/Testing)
   - Quick setup with Docker Compose
   - Easy local testing
   - See [Docker Setup](#docker-setup) below
   - Quick start: `./quick-start.sh`

3. **Kubernetes Deployment**
   - Run as a Deployment behind a LoadBalancer Service
   - ConfigMap + Secret driven; scales horizontally
   - See [Kubernetes Setup](#kubernetes-setup) below

4. **Traditional NGINX Installation** (Manual)
   - Direct installation on VM or bare metal
   - Full control over configuration
   - See [Manual Installation](#manual-installation) below

## Directory Structure

```
api-gateway/
├── nginx.yml                       # BOSH deployment manifest
├── deploy-bosh.sh                  # BOSH deployment helper script
├── vars.yml.example                # BOSH variables template
├── nginx.conf                      # Main NGINX configuration
├── conf.d/
│   └── vcenter-proxy.conf         # vCenter proxy configuration
├── ssl/
│   ├── README.md                  # SSL certificate documentation
│   └── generate-self-signed-cert.sh  # Self-signed cert generator
├── docker-compose.yml              # Docker Compose configuration
├── Dockerfile                      # Docker image definition
├── quick-start.sh                  # Docker quick start script
├── k8s/
│   ├── configmap.yaml             # nginx.conf + vcenter-proxy.conf.template
│   ├── secret.yaml                # TLS cert/key (placeholder)
│   ├── deployment.yaml            # Deployment with env-driven VCENTER_HOST
│   ├── service.yaml               # LoadBalancer Service (443/80)
│   └── route.yaml                 # OpenShift Route with TLS passthrough (optional)
├── README.md                       # This file
└── BOSH-DEPLOYMENT.md             # Detailed BOSH deployment guide
```

## Prerequisites

### For BOSH Deployment
- BOSH CLI installed and configured
- Access to BOSH Director
- NGINX BOSH release (version 1.21.6+)

### For Docker Deployment
- Docker and docker-compose installed
- OpenSSL (included in Docker image)

### For Kubernetes Deployment
- A Kubernetes cluster (1.24+) and `kubectl` configured against it
- Cluster support for `LoadBalancer` Services, or an Ingress controller if you prefer to front the gateway with Ingress
- TLS cert and key for the gateway-facing connection (self-signed via `ssl/generate-self-signed-cert.sh` is fine for dev)

### For Manual Installation
- NGINX 1.18+ (with SSL and HTTP/2 support)
- OpenSSL (for certificate generation)

### Common Requirements (All Methods)
- Network connectivity between NGINX gateway and vCenter
- Network connectivity between Bosh Director and NGINX gateway

## Quick Start

### BOSH Deployment (Recommended)

```bash
# 1. Edit nginx.yml and update vcenter_host
vi nginx.yml  # Change vcenter_host to your vCenter hostname/IP

# 2. (Optional) Copy and edit variables file
cp vars.yml.example vars.yml
vi vars.yml

# 3. Deploy
./deploy-bosh.sh

# Or manually:
bosh -d vcenter-gateway deploy nginx.yml -l vars.yml
```

See [BOSH-DEPLOYMENT.md](BOSH-DEPLOYMENT.md) for complete instructions.

### Docker Deployment

```bash
# 1. Edit configuration
vi conf.d/vcenter-proxy.conf  # Update VCENTER_HOST

# 2. Run quick start
./quick-start.sh
```

### Kubernetes Deployment

```bash
# 1. Create the TLS secret from your gateway cert/key
kubectl create secret tls api-gateway-tls \
  --cert=ssl/gateway.crt --key=ssl/gateway.key

# 2. Set your vCenter host in the Deployment env
vi k8s/deployment.yaml  # set VCENTER_HOST value

# 3. Apply the manifests
kubectl apply -f k8s/configmap.yaml -f k8s/deployment.yaml -f k8s/service.yaml

# 4. Grab the external IP
kubectl get svc api-gateway
```

## BOSH Deployment

For production deployments with BOSH, see the comprehensive guide: [BOSH-DEPLOYMENT.md](BOSH-DEPLOYMENT.md)

The BOSH deployment provides:
- Automatic SSL certificate generation
- Managed updates and healing
- Easy scaling and high availability
- Integration with BOSH cloud config
- Consistent deployment across environments

Key BOSH configuration file: `nginx.yml`

## Docker Setup

For development and testing with Docker, use the provided Docker Compose setup.

## Kubernetes Setup

The `k8s/` directory contains four manifests that deploy the gateway as a standard Kubernetes workload:

- `configmap.yaml` — holds `nginx.conf` and `vcenter-proxy.conf.template`. The template uses `${VCENTER_HOST}` and is rendered by the nginx image's built-in envsubst mechanism (files in `/etc/nginx/templates/` are processed to `/etc/nginx/conf.d/` at startup).
- `secret.yaml` — a `kubernetes.io/tls` Secret for the gateway-facing cert and key. Create it from your existing cert instead of editing the file:
  ```bash
  kubectl create secret tls api-gateway-tls \
    --cert=ssl/gateway.crt --key=ssl/gateway.key
  ```
- `deployment.yaml` — 2 replicas of `nginx:1.27-alpine`, mounts the ConfigMap and Secret, sets `VCENTER_HOST` via env, and uses `NGINX_ENVSUBST_FILTER=VCENTER_HOST` so only that variable is substituted (nginx's own `$vars` are preserved). Readiness and liveness probes hit `/nginx-health`.
- `service.yaml` — a `LoadBalancer` Service exposing 443 (and 80 for the HTTPS redirect). Access is restricted to the Bosh Director via `spec.loadBalancerSourceRanges` — edit the CIDR(s) there to match your Director's subnet, or remove the field to allow all sources.

### Configure

Before applying, edit the `VCENTER_HOST` env value in `k8s/deployment.yaml`:

```yaml
env:
  - name: VCENTER_HOST
    value: vcenter.example.com  # ← replace with your vCenter hostname/IP
```

And set the Bosh Director's IP (or subnet) in `k8s/service.yaml`:

```yaml
loadBalancerSourceRanges:
  - 192.0.2.42/32   # single Director IP
  # - 10.0.0.0/24   # …or a whole subnet if the Director can move
```

Use a `/32` CIDR to lock access to a single Director IP, or a wider CIDR for a subnet. Multiple entries are allowed. The cloud load balancer drops any traffic from outside these ranges before it reaches the pod. Supported on GKE, EKS, AKS, and most other cloud providers; on bare-metal clusters you'll need to enforce the restriction at your load balancer (MetalLB, external LB) or switch to the nginx `allow`/`deny` approach instead.

### Deploy

```bash
kubectl apply -f k8s/configmap.yaml -f k8s/deployment.yaml -f k8s/service.yaml
kubectl rollout status deploy/api-gateway
kubectl get svc api-gateway   # note the EXTERNAL-IP
```

Point your Bosh Director's CPI config at the Service's external IP/hostname (see [Configure Bosh Director](#6-configure-bosh-director)).

### Verify

```bash
# Health check through the LoadBalancer
curl -k https://<EXTERNAL-IP>/nginx-health

# Tail nginx logs across all replicas
kubectl logs -l app=api-gateway -f
```

All nginx access and error logs — including Bosh Director CPI calls proxied to vCenter — are written to `/dev/stdout` and `/dev/stderr`, so `kubectl logs` captures them directly. Entries use the `vcenter_api` log format with timing fields (`rt`, `uct`, `uht`, `urt`) and the request body.

With multiple replicas, requests are load-balanced across pods and each request appears in exactly one pod's logs. The `-l app=api-gateway` selector aggregates across all pods, which is usually what you want. To isolate a single pod:

```bash
kubectl logs <pod-name> -f
```

### Notes and Caveats

- **Logs**: the ConfigMap sends all nginx access/error logs to `/dev/stdout` and `/dev/stderr`, so `kubectl logs -l app=api-gateway` shows everything. If you'd rather ship logs to files on a persistent volume, change the `access_log`/`error_log` paths back to `/var/log/nginx/...` and mount a PVC at that path in place of the `emptyDir`.
- **Bare-metal clusters**: if your cluster doesn't provision `LoadBalancer` Services, change `spec.type` to `NodePort` in `service.yaml`, or front the Deployment with an Ingress. Since nginx here already terminates TLS, prefer an Ingress in TCP passthrough mode (or skip Ingress and use `NodePort`) rather than double-terminating TLS.
- **OpenShift**: prefer the Route in `k8s/route.yaml` over a `LoadBalancer` Service. The Route uses TLS passthrough so Bosh still sees the gateway's cert directly (no re-encryption at the router). Access restriction moves from `loadBalancerSourceRanges` on the Service to the `haproxy.router.openshift.io/ip_whitelist` annotation on the Route. You can either drop the Service entirely (Routes work against `ClusterIP` too — change the Service `type` to `ClusterIP` and skip `loadBalancerSourceRanges`), or keep the LoadBalancer Service alongside the Route.
- **Scaling**: the Deployment is stateless — adjust `spec.replicas` freely. A HorizontalPodAutoscaler works if you add CPU metrics-server.
- **Cert rotation**: re-create the `api-gateway-tls` Secret with the new cert; nginx does not auto-reload on Secret changes, so trigger a rollout: `kubectl rollout restart deploy/api-gateway`.

## Manual Installation

These instructions are for manually installing NGINX on a VM or bare metal. For BOSH deployment, see [BOSH-DEPLOYMENT.md](BOSH-DEPLOYMENT.md). For Docker, run `./quick-start.sh`.

### 1. Configure vCenter Backend

Edit `conf.d/vcenter-proxy.conf` and update the upstream server:

```nginx
upstream vcenter_backend {
    server YOUR_VCENTER_HOST:443 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
```

Replace `YOUR_VCENTER_HOST` with your actual vCenter hostname or IP address.

### 2. Generate SSL Certificates

For development/testing:
```bash
cd ssl
./generate-self-signed-cert.sh
```

For production, use proper CA-signed certificates (see `ssl/README.md`).

### 3. Deploy Configuration Files

Copy the configuration files to your NGINX installation:

```bash
# Backup existing configuration
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Copy new configuration
sudo cp nginx.conf /etc/nginx/nginx.conf
sudo cp -r conf.d/* /etc/nginx/conf.d/
sudo cp -r ssl/* /etc/nginx/ssl/

# Set proper permissions
sudo chown -R root:root /etc/nginx/
sudo chmod 600 /etc/nginx/ssl/*.key
sudo chmod 644 /etc/nginx/ssl/*.crt
```

### 4. Validate Configuration

Test the NGINX configuration:
```bash
sudo nginx -t
```

### 5. Start/Reload NGINX

```bash
# Start NGINX
sudo systemctl start nginx

# Or reload if already running
sudo systemctl reload nginx

# Enable auto-start on boot
sudo systemctl enable nginx
```

### 6. Configure Bosh Director

Update your Bosh Director's CPI configuration to point to the NGINX gateway instead of directly to vCenter.

**Get the Gateway IP/Hostname:**

- **BOSH Deployment**: Run `bosh -d vcenter-gateway instances` to get the IP
- **Docker Deployment**: Use the Docker host IP or `localhost` if running locally
- **Manual Installation**: Use the server's IP or hostname

**Update vCenter CPI Configuration:**

In your Bosh Director's `vcenter_cpi` configuration:

```yaml
vcenter:
  host: <NGINX_GATEWAY_IP_OR_HOSTNAME>  # Use gateway IP, not vCenter IP
  user: <vcenter_username>
  password: <vcenter_password>
  # ... other vcenter settings
```

**SSL Certificate Handling:**

If using self-signed certificates on the NGINX gateway, you have two options:

1. **Disable SSL verification** in Bosh CPI config (not recommended for production):
   ```yaml
   vcenter:
     host: <GATEWAY_IP>
     # ... other settings
     ssl_verify: false
   ```

2. **Add gateway certificate** to Bosh's trusted certificates (recommended):
   - Copy the gateway certificate from the gateway
   - Add it to your BOSH Director's trusted certificates

## Monitoring and Troubleshooting

### Check Logs

View access logs with detailed API call information:
```bash
sudo tail -f /var/log/nginx/vcenter-access.log
```

View error logs:
```bash
sudo tail -f /var/log/nginx/vcenter-error.log
```

### Health Check

Test the gateway health:
```bash
curl -k https://<NGINX_GATEWAY_IP>/nginx-health
```

Should return: `healthy`

### Test vCenter Connectivity

Test proxying to vCenter:
```bash
curl -k -X GET https://<NGINX_GATEWAY_IP>/api
```

This should return a vCenter API response (or authentication error if not authenticated).

### Common Issues

1. **Connection Refused**
   - Check NGINX is running: `sudo systemctl status nginx`
   - Check port 443 is open: `sudo netstat -tlnp | grep :443`

2. **502 Bad Gateway**
   - Verify vCenter hostname/IP in `vcenter-proxy.conf`
   - Check network connectivity: `ping <vcenter_host>`
   - Check vCenter is accessible: `curl -k https://<vcenter_host>`

3. **SSL Certificate Errors**
   - Verify certificates exist: `ls -l /etc/nginx/ssl/`
   - Check certificate permissions: `sudo chmod 600 /etc/nginx/ssl/*.key`
   - Validate certificate: `openssl x509 -in /etc/nginx/ssl/gateway.crt -text -noout`

4. **Slow Response Times**
   - Check NGINX logs for upstream timing: `grep "urt=" /var/log/nginx/vcenter-access.log`
   - Increase timeout values in `vcenter-proxy.conf` if needed

## Log Format

The custom log format includes:
- Client IP and user
- Request timestamp
- Request method, URI, and protocol
- Response status and size
- Request/response timing metrics:
  - `rt`: Total request time
  - `uct`: Upstream connect time
  - `uht`: Upstream header time
  - `urt`: Upstream response time

Example log entry:
```
192.168.1.100 - - [22/Jan/2026:10:30:45 +0000] "POST /sdk HTTP/2.0" 200 1234 "-" "Bosh/CPI" rt=0.523 uct="0.002" uht="0.120" urt="0.520"
```

## Security Considerations

1. **SSL Verification**: For production, enable `proxy_ssl_verify on` and provide vCenter's CA certificate
2. **Client Certificates**: Consider enabling mutual TLS with `ssl_verify_client on`
3. **Rate Limiting**: Add rate limiting if needed to prevent abuse
4. **Access Control**: Use firewall rules to restrict access to the gateway
5. **Log Rotation**: Configure logrotate for NGINX logs
6. **Certificate Rotation**: Monitor and rotate certificates before expiration

## Performance Tuning

For high-traffic environments:

1. **Worker Processes**: Adjust `worker_processes` in `nginx.conf` (default: auto)
2. **Connections**: Increase `worker_connections` if needed (default: 1024)
3. **Keepalive**: Tune keepalive connections to vCenter (default: 32)
4. **Buffer Sizes**: Adjust buffer sizes based on your API response sizes

## Advanced Configuration

### Enable SSL Verification for vCenter Backend

1. Obtain vCenter's CA certificate (see `ssl/README.md`)
2. Update `conf.d/vcenter-proxy.conf`:
   ```nginx
   proxy_ssl_verify on;
   proxy_ssl_trusted_certificate /etc/nginx/ssl/vcenter-ca.crt;
   ```

### Add Rate Limiting

Add to `http` block in `nginx.conf`:
```nginx
limit_req_zone $binary_remote_addr zone=vcenter_limit:10m rate=100r/s;
```

Add to server block in `vcenter-proxy.conf`:
```nginx
limit_req zone=vcenter_limit burst=200 nodelay;
```

### Enable Access Control

Add to server block in `vcenter-proxy.conf`:
```nginx
# Allow only specific IPs
allow 192.168.1.0/24;
allow 10.0.0.0/8;
deny all;
```

## License

This configuration is provided as-is for use with Bosh and vCenter deployments.

## Support

For issues or questions:
- Check NGINX error logs: `/var/log/nginx/vcenter-error.log`
- Validate configuration: `sudo nginx -t`
- Review Bosh Director logs for CPI errors
- Check vCenter API logs

# Gateway API Example Application

This example demonstrates how to deploy an application using the Gateway API setup in this cluster.

## Components

### 1. **Deployment** (`hello-app`)
- Simple HTTP echo server that responds with a custom message
- 3 replicas for high availability
- Resource limits and health checks configured
- Uses `hashicorp/http-echo` - a lightweight test server

### 2. **Service** (`hello-app`)
- ClusterIP service exposing the deployment on port 80
- Routes traffic to pods on port 8080

### 3. **HTTPRoute** (HTTPS)
- Attaches to the `https-example` listener on the Gateway
- Routes traffic from `https://staging.cluster.icaninto.space/hello` to the service
- Uses the Let's Encrypt TLS certificate automatically

### 4. **HTTPRoute** (HTTP Redirect)
- Attaches to the `http-example` listener on the Gateway
- Redirects HTTP traffic to HTTPS with a 301 status code

## Deployment Instructions

### Deploy the application:
```bash
kubectl apply -f examples/gateway-api-example.yaml
```

### Verify deployment:
```bash
# Check pods
kubectl get pods -n demo

# Check service
kubectl get svc -n demo

# Check HTTPRoutes
kubectl get httproute -n demo

# Check HTTPRoute status (should show "Accepted")
kubectl describe httproute hello-app-https -n demo
```

### Test the application:

**From inside the cluster:**
```bash
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- \
  curl -v https://staging.cluster.icaninto.space/hello
```

**From your local machine (once DNS propagates):**
```bash
# Test HTTPS
curl https://staging.cluster.icaninto.space/hello

# Test HTTP redirect
curl -v http://staging.cluster.icaninto.space/hello
# Should return 301 redirect to HTTPS
```

## Expected Response

```
Hello from Gateway API! 🚀
```

## How It Works

1. **External DNS** automatically creates DNS A/AAAA records for `staging.cluster.icaninto.space` pointing to the Gateway's load balancer IP

2. **Traffic flow**:
   ```
   Internet → Hetzner LB (91.98.3.104) 
   → Cilium Gateway (port 443) 
   → HTTPRoute (matches /hello path)
   → Service (hello-app:80)
   → Pod (hello-app:8080)
   ```

3. **TLS termination** happens at the Gateway using the Let's Encrypt certificate issued via DNS-01 challenge

4. **HTTP to HTTPS redirect** is handled by the separate HTTPRoute attached to the HTTP listener

## Customizing for Your Own Application

To deploy your own application with Gateway API:

1. **Create your Deployment and Service** in any namespace
   
2. **Create an HTTPRoute** that references:
   - `parentRefs`: Point to `cilium-gateway` in `ingress` namespace
   - `sectionName`: Use `https-example` for HTTPS or `http-example` for HTTP
   - `hostnames`: Must match the Gateway listener hostname
   - `backendRefs`: Point to your service name and port

3. **External DNS will automatically**:
   - Create DNS records based on the HTTPRoute hostnames
   - Update them when the Gateway IP changes
   - Clean up records when HTTPRoutes are deleted

4. **Cert-manager will automatically**:
   - Issue TLS certificates for hostnames on the Gateway
   - Renew certificates before expiry
   - Store certificates in the referenced secret

## Multiple Applications / Routes

You can deploy multiple applications behind the same Gateway by:

### Option 1: Path-based routing
```yaml
# App 1: /api/*
- matches:
  - path:
      type: PathPrefix
      value: /api

# App 2: /web/*
- matches:
  - path:
      type: PathPrefix
      value: /web
```

### Option 2: Host-based routing
Deploy different HTTPRoutes with different hostnames:
- `app1.cluster.icaninto.space`
- `app2.cluster.icaninto.space`

Each will get its own TLS certificate and DNS record automatically.

### Option 3: Header/Query-based routing
```yaml
- matches:
  - headers:
    - name: x-api-version
      value: v2
  backendRefs:
  - name: app-v2
```

## Cleanup

To remove the example application:
```bash
kubectl delete -f examples/gateway-api-example.yaml
```

External DNS will automatically remove the DNS records (if they were created for this HTTPRoute).

## Troubleshooting

### HTTPRoute not accepted
```bash
kubectl describe httproute <name> -n <namespace>
```
Check the `Conditions` section for errors like:
- `NotAllowedByListeners`: Check `allowedRoutes` in Gateway listeners
- `NoMatchingListenerHostname`: Hostname doesn't match any Gateway listener
- `BackendNotFound`: Service doesn't exist

### Certificate not ready
```bash
kubectl get certificate -n ingress
kubectl describe certificate example-tls -n ingress
```

### DNS not resolving
```bash
# Check External DNS logs
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=50

# Check DNS records
dig +short staging.cluster.icaninto.space
```

### Service unreachable
```bash
# Check if pods are running
kubectl get pods -n demo

# Check service endpoints
kubectl get endpoints -n demo

# Test service directly
kubectl run debug --rm -i --restart=Never --image=curlimages/curl -- \
  curl -v http://hello-app.demo.svc.cluster.local
```

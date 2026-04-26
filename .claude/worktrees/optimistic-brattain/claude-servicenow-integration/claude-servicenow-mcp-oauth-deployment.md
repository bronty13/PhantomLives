# ServiceNow MCP Server — OAuth 2.0 Enterprise Deployment Guide

Full deployment and configuration for `echelon-ai-labs/servicenow-mcp` using OAuth 2.0 with secure secret storage.

---

## Prerequisites

| Requirement | Minimum Version |
|---|---|
| Python | 3.11+ |
| ServiceNow | Washington DC release or later |
| pip | Latest |
| Docker (optional) | 20.10+ |
| Kubernetes (optional) | 1.25+ |

---

## Part 1: ServiceNow OAuth Application Setup

### Step 1.1 — Enable Client Credentials Grant Type

1. In ServiceNow, navigate to **System Properties > Security**
2. Find the property: `glide.oauth.inbound.client.credential.grant_type.enabled`
3. Set the value to `true`
4. Click **Save**

### Step 1.2 — Create the OAuth Application Registry

1. Navigate to **System OAuth > Application Registry**
2. Click **New**
3. Select **Create an OAuth API endpoint for external clients**
4. Fill in the fields:

| Field | Value | Notes |
|---|---|---|
| Name | `servicenow-mcp-client` | Human-readable label |
| Client ID | *(auto-generated)* | Copy after saving |
| Client Secret | *(auto-generated)* | Copy immediately after saving |
| Redirect URL | *(leave blank)* | Not used in Client Credentials flow |
| Login URL | *(leave blank)* | Not used in Client Credentials flow |
| Public Client | `false` | Must be confidential per OAuth 2.0 spec |
| Grant Types | `Client Credentials` | Select only this |

5. Click **Submit**
6. Reopen the record — copy both the **Client ID** and **Client Secret** immediately
7. Store them in your secret vault (see Part 3) — do not write them anywhere else

### Step 1.3 — Configure OAuth Scopes (Least Privilege)

In the OAuth Application Registry record, add only the scopes your use case requires:

| Scope | Purpose |
|---|---|
| `table_api_read` | Read ServiceNow table records |
| `table_api_create` | Create table records |
| `table_api_update` | Update table records |
| `api_table_list` | List available tables |
| `web_service_access` | General REST API access |
| `document_api` | Knowledge articles and documents |

> **Do NOT** grant `admin` or `super_admin` scopes to this client.

### Step 1.4 — Create a Dedicated Service Account

1. Navigate to **User Administration > Users**
2. Create a new user: e.g. `svc_claude_mcp`
3. Assign only the roles needed for your use cases (e.g. `itil`, `knowledge` — not `admin`)
4. Do not enable interactive login for this account
5. Associate the OAuth Application Registry with this service account

---

## Part 2: Install servicenow-mcp

```bash
pip install servicenow-mcp
```

Verify installation:

```bash
python -m servicenow_mcp.cli --help
servicenow-mcp-sse --help
```

---

## Part 3: Secure Secret Storage

Secrets must **never** be stored in plaintext `.env` files on developer machines or committed to version control. Choose the option that matches your infrastructure.

---

### Option A — HashiCorp Vault (Recommended for Enterprise)

**Store the secrets:**

```bash
vault kv put secret/servicenow-mcp \
  client_id="YOUR_CLIENT_ID" \
  client_secret="YOUR_CLIENT_SECRET" \
  instance_url="https://your-instance.service-now.com"
```

**Create an AppRole for the MCP server:**

```bash
vault auth enable approle

vault policy write servicenow-mcp-policy - <<EOF
path "secret/data/servicenow-mcp" {
  capabilities = ["read"]
}
EOF

vault write auth/approle/role/servicenow-mcp \
  token_policies="servicenow-mcp-policy" \
  token_ttl=1h \
  token_max_ttl=4h

vault read auth/approle/role/servicenow-mcp/role-id
vault write -f auth/approle/role/servicenow-mcp/secret-id
```

**Read secrets at server startup (`startup.sh`):**

```bash
#!/bin/bash
set -euo pipefail

SECRET=$(vault kv get -format=json secret/servicenow-mcp)

export SERVICENOW_CLIENT_ID=$(echo "$SECRET" | jq -r '.data.data.client_id')
export SERVICENOW_CLIENT_SECRET=$(echo "$SECRET" | jq -r '.data.data.client_secret')
export SERVICENOW_INSTANCE_URL=$(echo "$SECRET" | jq -r '.data.data.instance_url')
export SERVICENOW_AUTH_TYPE=oauth
export SERVICENOW_TOKEN_URL="${SERVICENOW_INSTANCE_URL}/oauth_token.do"

exec servicenow-mcp-sse \
  --instance-url="$SERVICENOW_INSTANCE_URL" \
  --host=0.0.0.0 \
  --port=8080
```

---

### Option B — AWS Secrets Manager

**Store the secrets:**

```bash
aws secretsmanager create-secret \
  --name servicenow-mcp/credentials \
  --secret-string '{
    "client_id": "YOUR_CLIENT_ID",
    "client_secret": "YOUR_CLIENT_SECRET",
    "instance_url": "https://your-instance.service-now.com"
  }'
```

**IAM policy for the MCP server's role:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:servicenow-mcp/credentials-*"
    }
  ]
}
```

**Read secrets at startup (`startup.sh`):**

```bash
#!/bin/bash
set -euo pipefail

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id servicenow-mcp/credentials \
  --query SecretString \
  --output text)

export SERVICENOW_CLIENT_ID=$(echo "$SECRET" | jq -r '.client_id')
export SERVICENOW_CLIENT_SECRET=$(echo "$SECRET" | jq -r '.client_secret')
export SERVICENOW_INSTANCE_URL=$(echo "$SECRET" | jq -r '.instance_url')
export SERVICENOW_AUTH_TYPE=oauth
export SERVICENOW_TOKEN_URL="${SERVICENOW_INSTANCE_URL}/oauth_token.do"

exec servicenow-mcp-sse \
  --instance-url="$SERVICENOW_INSTANCE_URL" \
  --host=0.0.0.0 \
  --port=8080
```

Attach the IAM role to your EC2 instance, ECS task, or Lambda — no static credentials needed.

---

### Option C — Azure Key Vault

**Store the secrets:**

```bash
az keyvault create --name servicenow-mcp-vault \
  --resource-group your-rg --location eastus

az keyvault secret set --vault-name servicenow-mcp-vault \
  --name client-id --value "YOUR_CLIENT_ID"

az keyvault secret set --vault-name servicenow-mcp-vault \
  --name client-secret --value "YOUR_CLIENT_SECRET"

az keyvault secret set --vault-name servicenow-mcp-vault \
  --name instance-url --value "https://your-instance.service-now.com"
```

**Assign Managed Identity access:**

```bash
az identity create --resource-group your-rg --name servicenow-mcp-identity

az keyvault set-policy --name servicenow-mcp-vault \
  --object-id <managed-identity-principal-id> \
  --secret-permissions get list
```

**Read secrets in a Python startup wrapper:**

```python
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

credential = DefaultAzureCredential()
client = SecretClient(
    vault_url="https://servicenow-mcp-vault.vault.azure.net/",
    credential=credential
)

os.environ["SERVICENOW_CLIENT_ID"] = client.get_secret("client-id").value
os.environ["SERVICENOW_CLIENT_SECRET"] = client.get_secret("client-secret").value
os.environ["SERVICENOW_INSTANCE_URL"] = client.get_secret("instance-url").value
os.environ["SERVICENOW_AUTH_TYPE"] = "oauth"
os.environ["SERVICENOW_TOKEN_URL"] = os.environ["SERVICENOW_INSTANCE_URL"] + "/oauth_token.do"

# Then start the MCP server
import subprocess
subprocess.run(["servicenow-mcp-sse", "--host=0.0.0.0", "--port=8080"])
```

---

### Option D — macOS Keychain (Individual Developer / Local Dev Only)

> Not suitable for production. Use for local development only.

**Store secrets:**

```bash
security add-generic-password -a servicenow-mcp -s client_id -w "YOUR_CLIENT_ID"
security add-generic-password -a servicenow-mcp -s client_secret -w "YOUR_CLIENT_SECRET"
security add-generic-password -a servicenow-mcp -s instance_url -w "https://your-instance.service-now.com"
```

**Read and export at startup:**

```bash
#!/bin/bash
export SERVICENOW_CLIENT_ID=$(security find-generic-password -a servicenow-mcp -s client_id -w)
export SERVICENOW_CLIENT_SECRET=$(security find-generic-password -a servicenow-mcp -s client_secret -w)
export SERVICENOW_INSTANCE_URL=$(security find-generic-password -a servicenow-mcp -s instance_url -w)
export SERVICENOW_AUTH_TYPE=oauth
export SERVICENOW_TOKEN_URL="${SERVICENOW_INSTANCE_URL}/oauth_token.do"

python -m servicenow_mcp.cli
```

---

## Part 4: Deploy as a Centralized Service

Running the MCP server centrally means users connect to it — no one stores secrets locally.

### Option A — Docker

**Dockerfile:**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install servicenow-mcp awscli jq

COPY startup.sh .
RUN chmod +x startup.sh

EXPOSE 8080

ENTRYPOINT ["./startup.sh"]
```

**Build and run:**

```bash
docker build -t servicenow-mcp:latest .

docker run -d \
  --name servicenow-mcp \
  -p 8080:8080 \
  -e AWS_REGION=us-east-1 \
  servicenow-mcp:latest
```

---

### Option B — Kubernetes

```yaml
# servicenow-mcp.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mcp-services
---
apiVersion: v1
kind: Secret
metadata:
  name: servicenow-mcp-secret
  namespace: mcp-services
type: Opaque
# Values are base64-encoded — use your vault to populate these at deploy time
# Never commit plaintext values to git
data:
  client_id: <base64-encoded>
  client_secret: <base64-encoded>
  instance_url: <base64-encoded>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: servicenow-mcp
  namespace: mcp-services
spec:
  replicas: 2
  selector:
    matchLabels:
      app: servicenow-mcp
  template:
    metadata:
      labels:
        app: servicenow-mcp
    spec:
      containers:
      - name: servicenow-mcp
        image: your-registry/servicenow-mcp:latest
        ports:
        - containerPort: 8080
        env:
        - name: SERVICENOW_AUTH_TYPE
          value: "oauth"
        - name: SERVICENOW_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: servicenow-mcp-secret
              key: client_id
        - name: SERVICENOW_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: servicenow-mcp-secret
              key: client_secret
        - name: SERVICENOW_INSTANCE_URL
          valueFrom:
            secretKeyRef:
              name: servicenow-mcp-secret
              key: instance_url
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: servicenow-mcp
  namespace: mcp-services
spec:
  selector:
    app: servicenow-mcp
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: servicenow-mcp-restrict
  namespace: mcp-services
spec:
  podSelector:
    matchLabels:
      app: servicenow-mcp
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: developer-tools
    ports:
    - protocol: TCP
      port: 8080
```

**Deploy:**

```bash
kubectl apply -f servicenow-mcp.yaml
kubectl -n mcp-services get pods
kubectl -n mcp-services logs -l app=servicenow-mcp
```

---

## Part 5: Connect Claude to the MCP Server

### Claude Code (CLI)

```bash
# Connect to the centralized SSE server
claude mcp add --transport http servicenow \
  http://servicenow-mcp.your-company.internal:8080/mcp

# Verify connection
claude mcp list

# Check available tools
claude mcp get servicenow
```

If your internal gateway requires a bearer token:

```bash
claude mcp add --transport http servicenow \
  https://api-gateway.your-company.com/servicenow-mcp \
  --header "Authorization: Bearer YOUR_GATEWAY_TOKEN"
```

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "servicenow": {
      "command": "npx",
      "args": [
        "mcp-remote@latest",
        "--transport", "http",
        "https://servicenow-mcp.your-company.internal:8080/mcp"
      ]
    }
  }
}
```

> Claude Desktop does not natively support remote HTTP MCP servers without the `mcp-remote` wrapper.

Restart Claude Desktop after editing the config.

---

## Part 6: Verify the OAuth Flow

Test token acquisition before deploying:

```bash
curl -X POST https://your-instance.service-now.com/oauth_token.do \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET"
```

Expected response:

```json
{
  "access_token": "abc123...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

Test the MCP server health:

```bash
curl -s http://servicenow-mcp.your-company.internal:8080/health | jq .
```

---

## Part 7: Production Checklist

### Security
- [ ] OAuth Application Registry created with Client Credentials grant type
- [ ] `Public Client` set to `false`
- [ ] Client ID and secret stored in Vault / Secrets Manager / Key Vault
- [ ] No secrets in `.env` files, source code, or CI/CD logs
- [ ] MCP server deployed on private network only (not internet-facing)
- [ ] TLS/HTTPS enabled with a valid internal certificate
- [ ] OAuth scopes limited to minimum required — no admin scopes
- [ ] Service account has no interactive login capability
- [ ] Secret rotation policy defined (30–90 days)

### Operations
- [ ] Health check endpoint monitored
- [ ] Token refresh verified to work beyond 30-minute sessions
- [ ] Logging enabled — OAuth token requests recorded (not token values)
- [ ] At least 2 replicas deployed for availability
- [ ] Rollback procedure documented

### User Access
- [ ] Claude Code users pointed to centralized server URL
- [ ] Claude Desktop users have updated `claude_desktop_config.json`
- [ ] Access to the MCP server restricted by network policy or gateway auth
- [ ] Usage audited via ServiceNow AI Control Tower (if enabled)

---

## Troubleshooting

### No tools appear after connecting

1. Check OAuth scopes — add `table_api_read`, `api_table_list`, `web_service_access`
2. Verify the service account has the appropriate ServiceNow roles
3. Confirm `SERVICENOW_INSTANCE_URL` exactly matches the OAuth registry instance URL
4. Test token acquisition manually (see Part 6)

### Token refresh failures after ~30 minutes

```bash
# Check server logs for oauth_token.do errors
docker logs servicenow-mcp | grep -i oauth

# Verify token URL is reachable from the server
curl -v https://your-instance.service-now.com/oauth_token.do
```

### "Invalid client type" error in ServiceNow

Set `Public Client` to `false` in the OAuth Application Registry. Client Credentials requires a confidential client.

### ServiceNow demands a Redirect URI

Leave Redirect URI blank. It is not required for Client Credentials grant type per OAuth 2.0 spec (RFC 6749 Section 4.4).

---

## References

- [servicenow-mcp GitHub Repository](https://github.com/echelon-ai-labs/servicenow-mcp)
- [ServiceNow OAuth 2.0 Setup](https://www.servicenow.com/community/developer-articles/oauth-2-0-setup-in-servicenow/ta-p/3307347)
- [ServiceNow Client Credentials Grant Type](https://support.servicenow.com/kb?id=kb_article_view&sysparm_article=KB1645212)
- [Claude Code MCP Configuration](https://code.claude.com/docs/en/mcp)
- [HashiCorp Vault ServiceNow Integration](https://developer.hashicorp.com/vault/docs/platform/servicenow)
- [AWS Secrets Manager for ServiceNow](https://www.servicenow.com/community/itom-articles/using-aws-secrets-manager-as-a-credential-store/ta-p/2625203)

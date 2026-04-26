# Claude + ServiceNow Integration Guide

## Your Three Integration Options

**Option 1: Native Build Agent (Easiest — Recommended)**
- ServiceNow has an official partnership with Anthropic (January 2026)
- Claude is the **default AI model** powering **ServiceNow Build Agent**
- Requires **Zurich release or later**
- Enables natural language app/automation building natively — no additional setup if you're on Zurich+

**Option 2: ServiceNow MCP Server (For Claude Desktop/Code users)**
- Community-maintained: `echelon-ai-labs/servicenow-mcp` on GitHub / PyPI
- Lets Claude Desktop or Claude Code interact directly with your ServiceNow instance
- Supports Basic Auth, OAuth 2.0, API Key

**Option 3: Direct REST API (Custom workflows)**
- Call the Anthropic API from ServiceNow Scripted REST APIs or Flow Designer
- Most flexible, most effort

---

## Admin Setup — Step by Step

### Step 1: Verify Your ServiceNow Version
- Check your instance is on **Zurich release or later** for native Build Agent
- If not, plan an upgrade or fall back to Option 2/3

### Step 2: Enable AI Control Tower (Governance Layer)
1. Go to **Plugin Manager** → search "AI Control Tower" → Install
2. Establish governance roles: Model Owners, Compliance Leads, Data Stewards
3. Register Claude in the model registry (version, use cases, data sources)
4. Configure audit/compliance mappings (GDPR, HIPAA, etc.)
5. Set up usage monitoring dashboard

### Step 3: Configure Authentication
- **For enterprise multi-user:** Set up OAuth 2.0 with Authorization Code flow
- **For service-to-service:** Store Anthropic API key in ServiceNow **Credential Store** (never hardcode it)
- OAuth is strongly recommended for user-level attribution and auditing

### Step 4: Set User Permissions via ACLs
- Assign Build Agent access through ServiceNow **Access Control Lists**
- Role-based: developers, admins, business users get different tool access
- The MCP server will inherit the ServiceNow user's existing permissions

---

## Enterprise Rollout for Users

### If using Build Agent (Zurich+)
1. Enable the plugin tenant-wide
2. Assign the `sn_build_agent.user` role (or equivalent) to groups/users
3. Point users to the Build Agent interface — no client-side setup needed

### If deploying MCP Server for power users

```bash
pip install servicenow-mcp
```

`.env` per user or shared service account:

```env
SERVICENOW_INSTANCE_URL=https://your-instance.service-now.com
SERVICENOW_AUTH_TYPE=oauth   # recommended for multi-user
SERVICENOW_USERNAME=your-username
SERVICENOW_PASSWORD=your-password
```

- Deploy on internal infrastructure (not per-laptop) for enterprise
- Use short-lived OAuth tokens (15–60 min)
- Map ServiceNow ACLs to control what each user can do through Claude

### If using Direct REST API

Call Claude from a ServiceNow Scripted REST API or Flow Designer step:

```bash
curl -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: YOUR_ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-opus-4-6",
    "max_tokens": 2048,
    "messages": [{
      "role": "user",
      "content": "Summarize this ServiceNow ticket: [ticket data]"
    }]
  }'
```

---

## Security Checklist

| Item | Action |
|---|---|
| API Keys | Store in ServiceNow Credential Store, rotate regularly |
| Multi-user auth | Use OAuth 2.0, not shared API keys |
| Data residency | Review Anthropic's data retention policy for regulated data |
| Audit trail | AI Control Tower logs all Claude usage per user |
| Permissions | Claude inherits ServiceNow ACL restrictions |

---

## Quickstart Checklist

- [ ] Confirm ServiceNow is on Zurich release
- [ ] Install AI Control Tower plugin
- [ ] Choose integration path (Build Agent / MCP / REST)
- [ ] Configure OAuth 2.0 app in ServiceNow
- [ ] Register Claude in AI model registry
- [ ] Pilot with 10–20 users, then full rollout

---

## Key Resources

- Anthropic + ServiceNow partnership: `anthropic.com/news/servicenow-anthropic-claude`
- MCP server: `github.com/echelon-ai-labs/servicenow-mcp`
- AI Control Tower docs: `servicenow.com/products/ai-control-tower.html`
- Low-code alternative: n8n has pre-built Claude + ServiceNow nodes

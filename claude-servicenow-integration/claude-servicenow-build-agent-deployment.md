# ServiceNow Build Agent + Claude — Enterprise Deployment Guide

Native integration using ServiceNow Build Agent with Claude as the default AI model.

> **Partnership Background:** Anthropic and ServiceNow announced an official partnership in January 2026. Claude is the default AI model powering Build Agent. ServiceNow has deployed Claude internally to 29,000+ employees.

> **Honest scope note:** Some granular admin steps (exact plugin IDs, Claude model selection UI path) are only available through ServiceNow's enterprise support channels, not public documentation. This guide covers everything confirmed and flags where to engage ServiceNow/Anthropic directly.

---

## Prerequisites

### ServiceNow Release

| Requirement | Minimum Version |
|---|---|
| Build Agent | Zurich Patch 1 (28.1.0) or Yokohama Patch 8 (27.8.0) |
| AI Control Tower | Yokohama or later (recommended) |
| ServiceNow IDE | 3.3.1+ |
| Unified Developer Core plugin | 28.1.1+ |

Check your version: navigate to `https://your-instance.service-now.com/stats.do` and look for **Build name**.

### Licensing

| Tier | Entitlement |
|---|---|
| Personal Developer Instance (PDI) | 10 prompts/month (free) |
| Trial (ServiceNow Store) | 25 interactions / 30 days |
| **Production Enterprise** | Unlimited — requires **Now Assist for Creator** license |

> **Action required:** Contact your ServiceNow account team to confirm your instance includes "Now Assist for Creator" before planning an enterprise rollout. Without this license, users hit the 25 prompt/month cap.

### Admin Roles Needed to Configure

- `admin` or `maint` role on your ServiceNow instance
- Access to **Plugin Manager** and **ServiceNow Store**
- Access to **AI Governance Workspace** (for AI Control Tower)

---

## Part 1: Enable Build Agent

### Step 1.1 — Activate the Plugin

1. In ServiceNow, navigate to **System Definition > Plugins** (or type `v_plugin.list` in the nav bar)
2. Search for **"Build Agent"**
3. If listed, click **Activate/Upgrade**
4. If not listed, go to the **ServiceNow Store** and search for "Build Agent"
   - Store App ID (trial): `0b1eae7ec3a4b690bc9a989f0501316c`
   - For production, search the store and request the licensed version through your ServiceNow account team

> **Note:** On PDIs and some Zurich/Yokohama instances, Build Agent may be pre-installed. Check **System Definition > Plugins** for status `Active` before attempting to install.

### Step 1.2 — Verify Unified Developer Core

1. Navigate to **System Definition > Plugins**
2. Search for **"Unified Developer Core"**
3. Confirm it is `Active` and at version `28.1.1` or higher
4. If not, activate it before proceeding — Build Agent depends on it

### Step 1.3 — Confirm Claude is the Active Model

As of the January 2026 partnership, Claude is the default model for Build Agent. Confirm this in:

- **Now Assist Admin** > **AI Model Configuration** (exact path varies by release)
- Or contact ServiceNow Support to confirm Claude is set as the active Build Agent model on your instance

> **If you do not see Claude listed:** Open a ServiceNow support case referencing the Anthropic/ServiceNow partnership (January 2026) and request activation of Claude as the Build Agent model. ServiceNow manages the Anthropic credentials on your behalf — you do not supply an Anthropic API key.

---

## Part 2: Configure AI Control Tower (Governance)

AI Control Tower is ServiceNow's governance layer for all AI models, including Claude. It provides audit trails, compliance mapping, usage monitoring, and access control.

### Step 2.1 — Activate the AI Control Tower Plugin

1. Navigate to **System Definition > Plugins**
2. Search for **"AI Governance"** or **"AI Control Tower"**
3. Activate the plugin
4. Confirm the **AI Governance Workspace** appears in the left nav

### Step 2.2 — Establish Governance Roles

Assign these roles to appropriate people in your organization before configuring the model registry:

| Role | Responsibility |
|---|---|
| **AI Steward** | Primary governance authority — configures workspace, enforces AI practices |
| **AI Asset Owner** | Accountable for accuracy, lifecycle management, and value realization of each AI asset |
| **Model Owner** | Manages a specific AI model (e.g. Claude) — day-to-day oversight |
| **Compliance Lead / AI Accountable Officer** | Reviews AI requests, assigns assessments, signs off on regulatory compliance |
| **Data Steward** | Manages data governance activities tied to AI model inputs/outputs |

**To assign roles:**
1. Navigate to **User Administration > Users**
2. Open the user record
3. In the **Roles** tab, add the appropriate AI governance role

### Step 2.3 — Register Claude in the Model Registry

1. Open the **AI Governance Workspace**
2. Navigate to **Model Registry > New**
3. Fill in the model record:

| Field | Value |
|---|---|
| Name | `Claude (Anthropic)` |
| Version | Current version (confirm with ServiceNow) |
| Provider | Anthropic |
| Intended Use Cases | App development, code generation, debugging, test writing, documentation |
| Data Inputs | User prompts, code context, workflow context |
| Data Outputs | Generated code, natural language responses |
| Risk Level | Set per your organization's AI risk framework |
| Owner | Assign the Model Owner role holder |

4. Save the record

### Step 2.4 — Map Compliance Frameworks

1. In the model record, navigate to the **Compliance** tab
2. Add mappings to your applicable frameworks:

| Framework | When to Apply |
|---|---|
| GDPR | EU data or users |
| HIPAA | Healthcare data |
| SOC 2 | General enterprise |
| CPRA | California users |
| ISO 27001 | If your org is certified |

3. Assign the Compliance Lead as reviewer for each mapping
4. Document data flow: user prompt → Claude (via ServiceNow) → response back to user

### Step 2.5 — Configure Usage Monitoring

1. In **AI Governance Workspace**, navigate to **Performance Monitoring**
2. Set up dashboards for:
   - Prompt volume per user/group
   - Token consumption trends
   - Error/failure rates
   - Response quality metrics (if using feedback collection)
3. Configure alerts for anomalous usage (e.g. single user exceeding 10x average)

---

## Part 3: User Access and Role Management

### Step 3.1 — Understand Build Agent Access Tiers

| User Type | What They Can Do |
|---|---|
| **Developer** | Full Build Agent access — create apps, write/debug/test code, ask questions, generate documentation |
| **Business Analyst** | Natural language app and workflow creation — limited code editing |
| **System Administrator** | All of the above plus Build Agent configuration access |

### Step 3.2 — Assign Access via Groups

1. Navigate to **User Administration > Groups**
2. Create or select your target group (e.g. `AI Developers`, `Now Assist Users`)
3. Add the relevant Build Agent / Now Assist role to the group:
   - Search for roles containing `build_agent` or `now_assist` in **User Administration > Roles**
   - Assign the appropriate role to the group
4. Add users to the group

> **Exact role names** for Build Agent may vary by instance release. Run this query in your instance to find them:
> Navigate to `sys_user_role.list` and filter by name containing `build` or `assist`.

### Step 3.3 — Control Access by Department (Optional)

Use **Assignment Groups** or **ACLs** to limit Build Agent to specific teams during rollout:

1. Navigate to **Security > Access Control (ACL)**
2. Create rules scoped to the Build Agent tables/operations
3. Reference your user groups as the permission condition

---

## Part 4: Security and Data Governance

### How Data Flows

```
Developer prompt (in ServiceNow IDE / Build Agent UI)
        ↓
ServiceNow instance (your tenant)
        ↓
ServiceNow → Anthropic API (governed by ServiceNow/Anthropic enterprise agreement)
        ↓
Claude processes prompt
        ↓
Response returned to ServiceNow → displayed to developer
```

**Key points:**
- ServiceNow manages the Anthropic API credentials — you do not configure them
- Data is governed by ServiceNow's enterprise data processing agreement with Anthropic
- Prompts and responses are subject to your ServiceNow instance's data residency configuration
- AI Control Tower logs all interactions for audit purposes

### Data Residency

- Build Agent operates within your ServiceNow instance's regional hosting
- Review your ServiceNow data residency configuration under **System Properties > Cluster**
- For regulated industries (healthcare, finance): confirm with ServiceNow that your hosting region applies to AI model traffic before enabling for production use

### What to Review with Your Legal/Compliance Team

- [ ] ServiceNow's Data Processing Addendum (DPA) covering AI features
- [ ] Anthropic's data handling terms as they apply through ServiceNow's enterprise agreement
- [ ] Whether prompt content (which may include code, ticket data, or workflow logic) meets your data classification policies for cloud AI processing
- [ ] HIPAA Business Associate Agreement (BAA) if applicable — confirm ServiceNow's BAA covers Build Agent/Claude usage

---

## Part 5: Enterprise Rollout Plan

### Phase 1 — Pilot (Weeks 1–2)

- [ ] Confirm Now Assist for Creator license is active
- [ ] Activate Build Agent and Unified Developer Core plugins
- [ ] Enable AI Control Tower and assign governance roles
- [ ] Register Claude in model registry
- [ ] Enable for a pilot group of 10–20 developers
- [ ] Monitor usage via AI Control Tower dashboard
- [ ] Collect feedback on quality and any data concerns

### Phase 2 — Controlled Expansion (Weeks 3–4)

- [ ] Expand to all developers and power users
- [ ] Train business analysts on natural language app creation
- [ ] Define and document acceptable use policy for Build Agent
- [ ] Set up usage alerts for anomaly detection
- [ ] Complete compliance framework mapping in model registry

### Phase 3 — Full Enterprise Rollout (Week 5+)

- [ ] Enable for all licensed users
- [ ] Communicate to users: what Build Agent is, acceptable use, how to get help
- [ ] Assign ongoing Model Owner and AI Steward responsibilities
- [ ] Schedule quarterly governance reviews via AI Control Tower
- [ ] Plan secret/credential rotation review with ServiceNow account team (annually)

---

## Part 6: Known Capabilities and Limitations

### What Build Agent Can Do

- Generate ServiceNow application scaffolding from natural language descriptions
- Write, edit, and explain code in ServiceNow's scripting languages
- Debug existing scripts and workflows
- Write automated tests
- Generate documentation
- Answer questions about ServiceNow platform features and APIs

### Known Limitations

| Limitation | Detail |
|---|---|
| PDI usage cap | 10 prompts/month without Now Assist for Creator license |
| Release dependency | Requires Zurich Patch 1 or Yokohama Patch 8 minimum |
| IDE dependency | ServiceNow IDE 3.3.1+ required — web browser only access varies |
| No direct Anthropic API access | You do not configure or control the Anthropic API key — ServiceNow manages it |
| Governance gaps | Detailed admin configuration docs are currently available only via ServiceNow enterprise support, not public documentation |

---

## Part 7: Where to Get Help

### For Configuration Issues

- **ServiceNow Support:** Open a case and reference "Build Agent with Claude — January 2026 Anthropic Partnership"
- **ServiceNow Community:** `community.servicenow.com` — search "Build Agent" for peer discussions
- **Your ServiceNow Account Team:** Request the official "Now Assist for Creator Enterprise Deployment Guide"

### For Licensing and Commercial Questions

- **ServiceNow Account Team:** Confirm Now Assist for Creator SKU and pricing
- **Anthropic Enterprise:** `anthropic.com/contact-sales` — for questions about data handling under the ServiceNow partnership

### For Compliance Documentation

- Request ServiceNow's **Data Processing Addendum** covering Now Assist / Build Agent
- Request confirmation that your ServiceNow hosting region covers AI model traffic
- If HIPAA applies, request a BAA amendment covering Build Agent/Claude

---

## Production Checklist

### Before Go-Live

- [ ] ServiceNow instance on Zurich Patch 1 or Yokohama Patch 8+
- [ ] Now Assist for Creator license confirmed active
- [ ] Build Agent plugin active
- [ ] Unified Developer Core 28.1.1+ active
- [ ] Claude confirmed as active Build Agent model
- [ ] AI Control Tower plugin active
- [ ] Governance roles assigned (AI Steward, Model Owner, Compliance Lead, Data Steward)
- [ ] Claude registered in model registry with metadata and risk level
- [ ] Compliance framework mappings completed
- [ ] User groups created with appropriate Build Agent roles
- [ ] Usage monitoring dashboards configured
- [ ] Acceptable use policy documented and communicated
- [ ] Legal/compliance sign-off on data processing for AI features
- [ ] HIPAA BAA confirmed (if applicable)

---

## References

- [Anthropic + ServiceNow Partnership Announcement](https://www.anthropic.com/news/servicenow-anthropic-claude)
- [ServiceNow Newsroom — Anthropic Partnership](https://newsroom.servicenow.com/press-releases/details/2026/ServiceNow-and-Anthropic-partner-to-help-customers-build-AI-powered-applications-accelerate-time-to-value-and-apply-trusted-AI-to-critical-industries/default.aspx)
- [ServiceNow Build Agent Documentation](https://www.servicenow.com/docs/r/application-development/build-agent.html)
- [ServiceNow AI Control Tower](https://www.servicenow.com/products/ai-control-tower.html)
- [AI Control Tower Governance Roles](https://www.servicenow.com/community/admin-experience-blogs/introducing-the-servicenow-ai-control-tower-from-intelligent/ba-p/3261185)
- [ServiceNow Store — Build Agent](https://store.servicenow.com/store/app/0b1eae7ec3a4b690bc9a989f0501316c)

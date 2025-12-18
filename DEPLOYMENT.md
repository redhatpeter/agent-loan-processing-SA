# 🚀 One-Click Azure Deployment Guide

Deploy the Student Loan Processing Assistant to Azure Container Apps with automated provisioning of all required Azure resources.

## Prerequisites

1. **Azure CLI** installed ([Download here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
2. **Azure subscription** with contributor access
3. **Azure OpenAI access** (automatic approval may be required - this is handled by the script)

## Quick Start

### Option 1: Bash (Linux/Mac/WSL)

```bash
# Make script executable
chmod +x deploy-to-azure.sh

# Run deployment
./deploy-to-azure.sh
```

### Option 2: PowerShell (Windows)

```powershell
# Run deployment
.\deploy-to-azure.ps1
```

## What the Script Does

The deployment script automatically provisions **ALL** required Azure resources:

### Phase 1: Azure Infrastructure (Steps 1-4)
1. ✅ Creates Resource Group
2. ✅ Creates Azure Storage Account + Container
3. ✅ Creates Azure OpenAI Resource
4. ✅ Deploys GPT-4o Model

### Phase 2: Container Infrastructure (Steps 5-7)
5. ✅ Creates Azure Container Registry
6. ✅ Builds 3 container images (MCP, Backend, Frontend)
7. ✅ Creates Container Apps Environment

### Phase 3: Application Deployment (Steps 8-9)
8. ✅ Deploys 3 Container Apps (MCP Server, Backend API, Frontend)
9. ✅ Configures CORS and networking

**Total Time: ~15-20 minutes**

## Interactive Prompts

The script will ask you for:

| Prompt | Default | Purpose |
|--------|---------|---------|
| Resource Group Name | `rg-loan-processing` | Logical container for all resources |
| Azure Region | `eastus` | Geographic location |
| Unique Prefix | `loan1234` (random) | Makes resource names globally unique |
| GPT-4o Deployment Name | `gpt-4o` | Name for your OpenAI model deployment |

> **Note**: All Azure OpenAI credentials and storage connection strings are automatically retrieved and securely stored as Container App secrets.

## Resources Created

After deployment completes, you'll have:

| Resource Type | Name Pattern | Purpose |
|--------------|--------------|---------|
| Resource Group | `rg-loan-processing` | Container for all resources |
| Storage Account | `{prefix}storage` | Document storage (loan apps, bank statements) |
| Storage Container | `loan-documents` | Blob container for uploaded PDFs |
| Azure OpenAI | `{prefix}-openai` | GPT-4o for document extraction & agents |
| Container Registry | `{prefix}acr` | Private Docker image repository |
| Container Apps Env | `{prefix}-env` | Managed environment for apps |
| MCP Server | `mcp-server` | Loan approval business logic (internal) |
| Backend API | `backend-api` | FastAPI multi-agent orchestrator (external) |
| Frontend Web | `frontend-web` | React SPA chat interface (external) |

## Environment Variables (Automatically Configured)

### Backend API Environment Variables

```bash
# Azure OpenAI Configuration
AZURE_OPENAI_ENDPOINT=https://{prefix}-openai.openai.azure.com/
AZURE_OPENAI_KEY=secretref:azure-openai-key  # Stored as secret
AZURE_OPENAI_CHAT_DEPLOYMENT_NAME=gpt-4o

# Azure Storage Configuration (Entra ID Authentication)
AZURE_STORAGE_ACCOUNT={prefix}storage  # Storage account name
AZURE_STORAGE_CONTAINER=loan-documents
# Note: Uses Managed Identity - no connection strings or keys required

# MCP Server Configuration
LOAN_APPROVAL_MCP_URL=https://mcp-server.{env}.azurecontainerapps.io/mcp

# Application Configuration
PROFILE=prod
ENABLE_OTEL=false
CORS_ORIGINS=https://frontend-web.{env}.azurecontainerapps.io
```

### Frontend Environment Variables

```bash
VITE_API_URL=https://backend-api.{env}.azurecontainerapps.io
```

### MCP Server Environment Variables

```bash
PROFILE=prod
```

## Post-Deployment

After deployment, you'll receive:

```
🌐 Application URLs:
   Frontend:  https://frontend-web.xxx.eastus.azurecontainerapps.io
   Backend:   https://backend-api.xxx.eastus.azurecontainerapps.io
   MCP API:   https://mcp-server.xxx.eastus.azurecontainerapps.io

☁️  Azure Resources:
   Resource Group: rg-loan-processing
   Storage Account: loan1234storage
   OpenAI Resource: loan1234-openai
   Container Registry: loan1234acr
```

**Visit the Frontend URL to start using the application!**

## Cost Estimate

Based on Azure pricing (December 2025):

| Resource | Tier | Monthly Cost (Estimate) |
|----------|------|------------------------|
| Container Apps (3 apps) | Consumption | ~$30-60 |
| Azure Container Registry | Basic | ~$5 |
| Azure OpenAI GPT-4o | Standard | ~$50-200 |
| Azure Blob Storage | Standard LRS | ~$1-5 |
| **Total** | | **~$85-270/month** |

### Cost Optimization Tips

- Container Apps **scale to zero** when idle (dev/test environments)
- Use **Azure Cost Management** to set budget alerts
- Delete the resource group when testing is complete
- Consider **shared capacity** for non-production workloads

## Cleanup

To delete all resources and stop charges:

```bash
# Delete entire resource group (removes all resources)
az group delete --name rg-loan-processing --yes --no-wait
```

This removes:
- All 3 Container Apps
- Container Registry and images
- Container Apps Environment
- Azure OpenAI resource
- Storage Account and all blobs

## Monitoring & Troubleshooting

### View Backend Logs

```bash
az containerapp logs show \
  --name backend-api \
  --resource-group rg-loan-processing \
  --follow
```

### View MCP Server Logs

```bash
az containerapp logs show \
  --name mcp-server \
  --resource-group rg-loan-processing \
  --follow
```

### Check Health Endpoints

```bash
# Backend API health
curl https://backend-api.xxx.azurecontainerapps.io/api/status

# Frontend health
curl https://frontend-web.xxx.azurecontainerapps.io/health
```

### View All Resources

```bash
az resource list \
  --resource-group rg-loan-processing \
  --output table
```

### Common Issues

#### Issue: "Container Registry name already exists"

**Cause**: ACR names must be globally unique  
**Solution**: Use a different prefix when prompted (e.g., `loan5678`)

#### Issue: "Azure OpenAI deployment failed"

**Cause**: Quota limits or region availability  
**Solution**: 
- Try a different region: `eastus`, `westus2`, `northcentralus`
- Check your OpenAI quota in Azure Portal
- Request quota increase if needed

#### Issue: "Frontend can't connect to Backend"

**Cause**: DNS propagation or CORS misconfiguration  
**Solution**: 
- Wait 2-3 minutes for DNS propagation
- Check backend health: `curl https://BACKEND_URL/api/status`
- Verify CORS is set: Script automatically configures this in Step 9

#### Issue: "Document upload fails"

**Cause**: Storage container permissions  
**Solution**: 
- Verify container exists: `az storage container list --account-name {prefix}storage`
- Check backend logs for storage errors

## Manual Updates After Deployment

### Update Backend Environment Variable

```bash
az containerapp update \
  --name backend-api \
  --resource-group rg-loan-processing \
  --set-env-vars "NEW_VAR=new_value"
```

### Update Secret

```bash
az containerapp secret set \
  --name backend-api \
  --resource-group rg-loan-processing \
  --secrets "new-secret=secret-value"
```

### Scale Container App

```bash
az containerapp update \
  --name backend-api \
  --resource-group rg-loan-processing \
  --min-replicas 2 \
  --max-replicas 10
```

### Redeploy with New Image

```bash
# Rebuild and push new image
az acr build --registry loan1234acr \
  --image loan-backend:latest \
  --file src/backend/Dockerfile \
  src/backend

# Container App auto-updates with new image
# Or force restart:
az containerapp revision restart \
  --name backend-api \
  --resource-group rg-loan-processing
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Resource Group                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Container Apps Environment                    │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │  │
│  │  │   Frontend   │  │   Backend    │  │ MCP Server │ │  │
│  │  │  (External)  │─▶│  (External)  │─▶│ (Internal) │ │  │
│  │  │  Port 80     │  │  Port 8000   │  │ Port 8070  │ │  │
│  │  └──────────────┘  └──────────────┘  └────────────┘ │  │
│  │                           │                            │  │
│  └───────────────────────────┼────────────────────────────┘  │
│                              │                                │
│                              ▼                                │
│  ┌──────────────────────────────────────┐                   │
│  │       Azure OpenAI (GPT-4o)          │                   │
│  │  Document Extraction & Agents        │                   │
│  └──────────────────────────────────────┘                   │
│                              │                                │
│                              ▼                                │
│  ┌──────────────────────────────────────┐                   │
│  │    Azure Blob Storage                │                   │
│  │  Container: loan-documents           │                   │
│  └──────────────────────────────────────┘                   │
│                                                               │
│  ┌──────────────────────────────────────┐                   │
│  │   Azure Container Registry           │                   │
│  │  Private image repository            │                   │
│  └──────────────────────────────────────┘                   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Security Best Practices

✅ **Managed Identity Authentication**: Backend uses system-assigned managed identity for Azure Storage and OpenAI (no keys stored)  
✅ **RBAC Authorization**: Fine-grained role assignments (Storage Blob Data Contributor, Cognitive Services OpenAI User)  
✅ **Secrets Management**: OpenAI keys stored as Container App secrets (for backward compatibility)  
✅ **Network Isolation**: MCP Server uses internal ingress (not internet-accessible)  
✅ **CORS Configuration**: Backend only accepts requests from frontend domain  
✅ **Storage Security**: Blob public access disabled by default  
✅ **HTTPS**: All external endpoints use TLS/SSL automatically  
✅ **Zero-Trust**: Entra ID authentication eliminates credential exposure

## Production Recommendations

The deployment already includes production-ready security features:

✅ **Managed Identity**: Enabled - backend uses system-assigned identity  
✅ **RBAC**: Configured - proper role assignments for storage and OpenAI  
✅ **No Storage Keys**: Entra ID authentication eliminates key rotation needs

Additional considerations for production:

1. **Azure Key Vault**: Store OpenAI keys externally (optional enhancement)
   ```bash
   az keyvault create --name {prefix}-kv --resource-group rg-loan-processing
   ```

2. **Azure Front Door**: Global CDN and WAF
   ```bash
   az afd profile create --profile-name loan-afd --resource-group rg-loan-processing
   ```

3. **Application Insights**: Enhanced monitoring (already supported via ENABLE_OTEL)
   ```bash
   az monitor app-insights component create --app loan-insights --resource-group rg-loan-processing
   ```

4. **Managed Identity**: Replace API keys with identity-based auth
   ```bash
   az containerapp identity assign --name backend-api --resource-group rg-loan-processing --system-assigned
   ```

5. **Azure Cosmos DB**: Replace in-memory state with persistent storage
   ```bash
   az cosmosdb create --name {prefix}-cosmos --resource-group rg-loan-processing
   ```

## Support

- **Azure Container Apps**: [Official Documentation](https://learn.microsoft.com/azure/container-apps/)
- **Azure OpenAI**: [Service Documentation](https://learn.microsoft.com/azure/ai-services/openai/)
- **Microsoft Agent Framework**: [Framework Docs](https://learn.microsoft.com/agent-framework/)
- **Project Issues**: Report bugs or feature requests on GitHub

## Next Steps

1. ✅ Deploy using the script
2. ✅ Test the application via the Frontend URL
3. ✅ Upload sample loan documents (provided in `test_data/`)
4. ✅ Monitor logs and metrics
5. ✅ Configure custom domain (optional)
6. ✅ Set up CI/CD pipeline with GitHub Actions (optional)

---

**🎉 Happy Deploying!**

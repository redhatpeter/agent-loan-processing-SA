# Azure Container Apps Deployment Script (PowerShell)
$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "🚀 Azure Container Apps Deployment" -ForegroundColor Cyan
Write-Host "   Student Loan Processing Assistant" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Azure CLI is installed
if (!(Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Azure CLI is not installed. Please install it first:" -ForegroundColor Red
    Write-Host "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
}

# Check if logged in
try {
    az account show | Out-Null
} catch {
    Write-Host "⚠️  Not logged in to Azure. Please login..." -ForegroundColor Yellow
    az login
}

$SUBSCRIPTION = az account show --query name -o tsv
$SUBSCRIPTION_ID = az account show --query id -o tsv
Write-Host "📋 Using Azure subscription: $SUBSCRIPTION" -ForegroundColor Green
Write-Host ""

# Prompt for configuration
$RESOURCE_GROUP = Read-Host "Enter resource group name [e.g. rg-loan-processing]"
if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) { $RESOURCE_GROUP = "rg-loan-processing" }

$LOCATION = Read-Host "Enter Azure region [e.g. eastus]"
if ([string]::IsNullOrWhiteSpace($LOCATION)) { $LOCATION = "eastus" }

$defaultPrefix = "loan$(Get-Random -Minimum 1000 -Maximum 9999)"
Write-Host "Enter unique prefix for resources (lowercase, no special chars)"
$PREFIX = Read-Host "Prefix [$defaultPrefix]"
if ([string]::IsNullOrWhiteSpace($PREFIX)) { $PREFIX = $defaultPrefix }

# Convert prefix to lowercase and remove any special characters
$PREFIX = $PREFIX.ToLower() -replace '[^a-z0-9]', ''

# Validate prefix length (must be 3-20 chars for valid ACR name)
if ($PREFIX.Length -lt 3) {
    Write-Host "⚠️  Prefix too short. Using default: $defaultPrefix" -ForegroundColor Yellow
    $PREFIX = $defaultPrefix
} elseif ($PREFIX.Length -gt 20) {
    Write-Host "⚠️  Prefix too long. Truncating to 20 characters." -ForegroundColor Yellow
    $PREFIX = $PREFIX.Substring(0, 20)
}

# Derived names
# ACR name: lowercase alphanumeric only, no hyphens (Azure requirement)
$ACR_NAME = "${PREFIX}acr"
$ENVIRONMENT = "${PREFIX}-env"
# Storage account: lowercase alphanumeric only, 3-24 chars
$STORAGE_ACCOUNT = ("${PREFIX}storage").Substring(0, [Math]::Min(24, "${PREFIX}storage".Length))
$OPENAI_RESOURCE = "${PREFIX}-openai"
$BACKEND_APP = "backend-api"
$MCP_APP = "mcp-server"
$FRONTEND_APP = "frontend-web"
$STORAGE_CONTAINER = "loan-documents"

Write-Host ""
Write-Host "📝 Configuration Summary:" -ForegroundColor Cyan
Write-Host "   Resource Group: $RESOURCE_GROUP"
Write-Host "   Location: $LOCATION"
Write-Host "   Prefix: $PREFIX"
Write-Host "   Container Registry: $ACR_NAME"
Write-Host "   Storage Account: $STORAGE_ACCOUNT"
Write-Host "   OpenAI Resource: $OPENAI_RESOURCE"
Write-Host "   Environment: $ENVIRONMENT"
Write-Host ""

$CONFIRM = Read-Host "Continue with deployment? (yes/no)"
if ($CONFIRM -ne "yes") {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PHASE 1: Azure Infrastructure Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "🔧 Step 1/9: Creating resource group..." -ForegroundColor Yellow
az group create --name $RESOURCE_GROUP --location $LOCATION --output none
Write-Host "✅ Resource group created: $RESOURCE_GROUP" -ForegroundColor Green

Write-Host ""
Write-Host "🔧 Step 2/9: Creating Azure Storage Account..." -ForegroundColor Yellow
az storage account create `
  --name $STORAGE_ACCOUNT `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION `
  --sku Standard_LRS `
  --kind StorageV2 `
  --allow-blob-public-access false `
  --output none

# Get current identity (user or service principal) for RBAC assignment
Write-Host "   Detecting current Azure identity..." -ForegroundColor Gray
$CURRENT_USER_ID = $null
$CURRENT_USER_TYPE = $null

# Try to get signed-in user first
try {
    $CURRENT_USER_ID = az ad signed-in-user show --query id -o tsv 2>$null
    if ($CURRENT_USER_ID) {
        $CURRENT_USER_TYPE = "user"
        $userName = az ad signed-in-user show --query userPrincipalName -o tsv
        Write-Host "   ✓ Detected user account: $userName" -ForegroundColor Green
    }
} catch {
    $CURRENT_USER_ID = $null
}

if (-not $CURRENT_USER_ID) {
    # If that fails, try to get service principal or user via account
    $CURRENT_ACCOUNT = az account show --query user.name -o tsv
    
    if ($CURRENT_ACCOUNT -like "*@*") {
        # Still a user, but ad signed-in-user failed
        Write-Host "   ⚠️  Could not get user object ID. Trying account lookup..." -ForegroundColor Yellow
        try {
            $CURRENT_USER_ID = az ad user show --id $CURRENT_ACCOUNT --query id -o tsv 2>$null
            $CURRENT_USER_TYPE = "user"
        } catch {
            $CURRENT_USER_ID = $null
        }
    } else {
        # Service principal
        Write-Host "   ✓ Detected service principal: $CURRENT_ACCOUNT" -ForegroundColor Green
        try {
            $CURRENT_USER_ID = az ad sp show --id $CURRENT_ACCOUNT --query id -o tsv 2>$null
            $CURRENT_USER_TYPE = "service-principal"
        } catch {
            $CURRENT_USER_ID = $null
        }
    }
}

# Assign Storage Blob Data Contributor role to deployment identity
if ($CURRENT_USER_ID) {
    Write-Host "   Assigning Storage Blob Data Contributor role to deployment $CURRENT_USER_TYPE..." -ForegroundColor Gray
    try {
        az role assignment create `
          --role "Storage Blob Data Contributor" `
          --assignee $CURRENT_USER_ID `
          --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" `
          --output none 2>$null
    } catch {
        Write-Host "   ⚠️  Role assignment skipped (may already exist or insufficient permissions)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ⚠️  Could not determine current identity. Role assignment for deployment user skipped." -ForegroundColor Yellow
    Write-Host "   ℹ️  The backend managed identity will still receive necessary permissions." -ForegroundColor Cyan
}

# Create storage container using Azure AD auth
az storage container create `
  --name $STORAGE_CONTAINER `
  --account-name $STORAGE_ACCOUNT `
  --auth-mode login `
  --output none

Write-Host "✅ Storage Account created: $STORAGE_ACCOUNT" -ForegroundColor Green
Write-Host "   Container: $STORAGE_CONTAINER" -ForegroundColor Gray
Write-Host "   Authentication: Entra ID (Managed Identity)" -ForegroundColor Gray

Write-Host ""
Write-Host "🔧 Step 3/9: Creating Azure OpenAI resource..." -ForegroundColor Yellow


# Check if cognitive services provider is registered
$PROVIDER_STATE = az provider show --namespace Microsoft.CognitiveServices --query registrationState -o tsv
if ($PROVIDER_STATE -ne "Registered") {
    Write-Host "   Registering Microsoft.CognitiveServices provider..." -ForegroundColor Gray
    az provider register --namespace Microsoft.CognitiveServices --wait
}

# Create Azure OpenAI resource
az cognitiveservices account create `
  --name $OPENAI_RESOURCE `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION `
  --kind OpenAI `
  --sku S0 `
  --yes `
  --output none

# Get OpenAI key and endpoint
$AZURE_OPENAI_KEY = az cognitiveservices account keys list `
  --name $OPENAI_RESOURCE `
  --resource-group $RESOURCE_GROUP `
  --query key1 -o tsv

$AZURE_OPENAI_ENDPOINT = az cognitiveservices account show `
  --name $OPENAI_RESOURCE `
  --resource-group $RESOURCE_GROUP `
  --query properties.endpoint -o tsv

Write-Host "✅ Azure OpenAI resource created: $OPENAI_RESOURCE" -ForegroundColor Green
Write-Host "   Endpoint: $AZURE_OPENAI_ENDPOINT" -ForegroundColor Gray

Write-Host ""
Write-Host "🔧 Step 4/9: Deploying GPT-4o model..." -ForegroundColor Yellow
$OPENAI_DEPLOYMENT = Read-Host "Enter GPT-4o deployment name [e.g. gpt-4o]"
if ([string]::IsNullOrWhiteSpace($OPENAI_DEPLOYMENT)) { $OPENAI_DEPLOYMENT = "gpt-4o" }

az cognitiveservices account deployment create `
  --name $OPENAI_RESOURCE `
  --resource-group $RESOURCE_GROUP `
  --deployment-name $OPENAI_DEPLOYMENT `
  --model-name gpt-4o `
  --model-version "2024-08-06" `
  --model-format OpenAI `
  --sku-capacity 10 `
  --sku-name "Standard" `
  --output none

Write-Host "✅ GPT-4o model deployed: $OPENAI_DEPLOYMENT" -ForegroundColor Green

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PHASE 2: Container Infrastructure" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "🔧 Step 5/9: Creating Azure Container Registry..." -ForegroundColor Yellow
az acr create `
  --resource-group $RESOURCE_GROUP `
  --name $ACR_NAME `
  --sku Basic `
  --admin-enabled true `
  --output none
Write-Host "✅ Container Registry created: $ACR_NAME" -ForegroundColor Green

Write-Host ""
Write-Host "🔧 Step 6/9: Building and pushing container images..." -ForegroundColor Yellow
Write-Host "   This may take 5-10 minutes..." -ForegroundColor Gray

Write-Host "   Building MCP Server..." -ForegroundColor Cyan
az acr build --registry $ACR_NAME `
  --image loan-mcp:latest `
  --file src/biz_api/loan_approval/Dockerfile `
  src/biz_api/loan_approval

Write-Host "   Building Backend API..." -ForegroundColor Cyan
az acr build --registry $ACR_NAME `
  --image loan-backend:latest `
  --file src/backend/Dockerfile `
  src/backend

Write-Host "   Building Frontend..." -ForegroundColor Cyan
az acr build --registry $ACR_NAME `
  --image loan-frontend:latest `
  --file src/frontend/Dockerfile `
  src/frontend

Write-Host "✅ All images built and pushed to ACR" -ForegroundColor Green

Write-Host ""
Write-Host "🔧 Step 7/9: Creating Container Apps environment..." -ForegroundColor Yellow
az containerapp env create `
  --name $ENVIRONMENT `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION `
  --output none
Write-Host "✅ Container Apps environment created: $ENVIRONMENT" -ForegroundColor Green

# Get ACR credentials
$ACR_USERNAME = az acr credential show --name $ACR_NAME --query username -o tsv
$ACR_PASSWORD = az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv
$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer -o tsv

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PHASE 3: Application Deployment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "🔧 Step 8/9: Deploying container apps..." -ForegroundColor Yellow

Write-Host "   Creating registry credentials secret..." -ForegroundColor Gray
az containerapp env registry add `
  --name $ENVIRONMENT `
  --resource-group $RESOURCE_GROUP `
  --server $ACR_LOGIN_SERVER `
  --username $ACR_USERNAME `
  --password $ACR_PASSWORD `
  --output none

Write-Host "   Deploying MCP Server..." -ForegroundColor Cyan
az containerapp create `
  --name $MCP_APP `
  --resource-group $RESOURCE_GROUP `
  --environment $ENVIRONMENT `
  --image "$ACR_LOGIN_SERVER/loan-mcp:latest" `
  --target-port 8070 `
  --ingress internal `
  --min-replicas 1 `
  --max-replicas 2 `
  --cpu 0.5 `
  --memory 1.0Gi `
  --env-vars "PROFILE=prod" `
  --output none

$MCP_FQDN = az containerapp show --name $MCP_APP --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv
Write-Host "   ✅ MCP Server deployed: https://$MCP_FQDN" -ForegroundColor Green

Write-Host ""
Write-Host "   Deploying Backend API with Managed Identity..." -ForegroundColor Cyan
az containerapp create `
  --name $BACKEND_APP `
  --resource-group $RESOURCE_GROUP `
  --environment $ENVIRONMENT `
  --image "$ACR_LOGIN_SERVER/loan-backend:latest" `
  --target-port 8000 `
  --ingress external `
  --min-replicas 1 `
  --max-replicas 3 `
  --cpu 1.0 `
  --memory 2.0Gi `
  --system-assigned `
  --secrets "azure-openai-key=$AZURE_OPENAI_KEY" `
  --env-vars "PROFILE=prod" "LOAN_APPROVAL_MCP_URL=https://$MCP_FQDN/mcp" "AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT" "AZURE_OPENAI_KEY=secretref:azure-openai-key" "AZURE_OPENAI_CHAT_DEPLOYMENT_NAME=$OPENAI_DEPLOYMENT" "AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT" "AZURE_STORAGE_CONTAINER=$STORAGE_CONTAINER" "ENABLE_OTEL=false" `
  --output none

$BACKEND_FQDN = az containerapp show --name $BACKEND_APP --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv

# Get the managed identity principal ID
$BACKEND_IDENTITY = az containerapp show --name $BACKEND_APP --resource-group $RESOURCE_GROUP --query identity.principalId -o tsv

# Assign Storage Blob Data Contributor role to backend managed identity
Write-Host "   Assigning Storage Blob Data Contributor role to backend managed identity..." -ForegroundColor Gray
az role assignment create `
  --role "Storage Blob Data Contributor" `
  --assignee $BACKEND_IDENTITY `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" `
  --output none

# Assign Cognitive Services OpenAI User role to backend managed identity
Write-Host "   Assigning Cognitive Services OpenAI User role to backend managed identity..." -ForegroundColor Gray
az role assignment create `
  --role "Cognitive Services OpenAI User" `
  --assignee $BACKEND_IDENTITY `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$OPENAI_RESOURCE" `
  --output none

Write-Host "   ✅ Backend API deployed: https://$BACKEND_FQDN" -ForegroundColor Green
Write-Host "   ✅ RBAC roles assigned to managed identity" -ForegroundColor Green

Write-Host ""
Write-Host "   Deploying Frontend..." -ForegroundColor Cyan
az containerapp create `
  --name $FRONTEND_APP `
  --resource-group $RESOURCE_GROUP `
  --environment $ENVIRONMENT `
  --image "$ACR_LOGIN_SERVER/loan-frontend:latest" `
  --target-port 80 `
  --ingress external `
  --min-replicas 1 `
  --max-replicas 2 `
  --cpu 0.5 `
  --memory 1.0Gi `
  --env-vars "VITE_API_URL=https://$BACKEND_FQDN" `
  --output none

$FRONTEND_FQDN = az containerapp show --name $FRONTEND_APP --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv
Write-Host "   ✅ Frontend deployed: https://$FRONTEND_FQDN" -ForegroundColor Green

Write-Host ""
Write-Host "🔧 Step 9/9: Configuring CORS for backend..." -ForegroundColor Yellow
az containerapp update `
  --name $BACKEND_APP `
  --resource-group $RESOURCE_GROUP `
  --set-env-vars "CORS_ORIGINS=https://$FRONTEND_FQDN" `
  --output none
Write-Host "✅ CORS configured" -ForegroundColor Green

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "🌐 Application URLs:" -ForegroundColor Yellow
Write-Host "   Frontend:  https://$FRONTEND_FQDN" -ForegroundColor Green
Write-Host "   Backend:   https://$BACKEND_FQDN" -ForegroundColor Green
Write-Host "   MCP API:   https://$MCP_FQDN" -ForegroundColor Green
Write-Host ""
Write-Host "☁️  Azure Resources:" -ForegroundColor Yellow
Write-Host "   Resource Group: $RESOURCE_GROUP" -ForegroundColor Gray
Write-Host "   Storage Account: $STORAGE_ACCOUNT" -ForegroundColor Gray
Write-Host "   OpenAI Resource: $OPENAI_RESOURCE" -ForegroundColor Gray
Write-Host "   Container Registry: $ACR_NAME" -ForegroundColor Gray
Write-Host ""
Write-Host "💡 Tips:" -ForegroundColor Yellow
Write-Host "   • Visit https://$FRONTEND_FQDN to use the application"
Write-Host "   • Monitor logs: az containerapp logs show --name $BACKEND_APP -g $RESOURCE_GROUP --follow"
Write-Host "   • View resources: az resource list -g $RESOURCE_GROUP --output table"
Write-Host ""
Write-Host "🗑️  To delete all resources and stop charges:" -ForegroundColor Yellow
Write-Host "   az group delete --name $RESOURCE_GROUP --yes --no-wait"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

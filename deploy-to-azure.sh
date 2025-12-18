#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Azure Container Apps Deployment"
echo "   Student Loan Processing Assistant"
echo "=========================================="
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first:"
    echo "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "⚠️  Not logged in to Azure. Please login..."
    az login
fi

# Get current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "📋 Using Azure subscription: $SUBSCRIPTION"
echo ""

# Prompt for configuration
read -p "Enter resource group name [e.g. rg-loan-processing]: " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-loan-processing}

read -p "Enter Azure region [e.g. eastus]: " LOCATION
LOCATION=${LOCATION:-eastus}

read -p "Enter unique prefix for resources (lowercase, no special chars) [loan$((RANDOM%9000+1000))]: " PREFIX
PREFIX=${PREFIX:-loan$((RANDOM%9000+1000))}

# Convert prefix to lowercase and remove any special characters
PREFIX=$(echo "$PREFIX" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

# Validate prefix length (must be 3-20 chars for valid ACR name)
if [ ${#PREFIX} -lt 3 ]; then
    echo "⚠️  Prefix too short. Using default: loan$((RANDOM%9000+1000))"
    PREFIX="loan$((RANDOM%9000+1000))"
elif [ ${#PREFIX} -gt 20 ]; then
    echo "⚠️  Prefix too long. Truncating to 20 characters."
    PREFIX=${PREFIX:0:20}
fi

# Derived names
# ACR name: lowercase alphanumeric only, no hyphens (Azure requirement)
ACR_NAME="${PREFIX}acr"
ENVIRONMENT="${PREFIX}-env"
# Storage account: lowercase alphanumeric only, 3-24 chars
STORAGE_ACCOUNT=$(echo "${PREFIX}storage" | cut -c1-24)
OPENAI_RESOURCE="${PREFIX}-openai"
BACKEND_APP="backend-api"
MCP_APP="mcp-server"
FRONTEND_APP="frontend-web"
STORAGE_CONTAINER="loan-documents"

echo ""
echo "📝 Configuration Summary:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Location: $LOCATION"
echo "   Prefix: $PREFIX"
echo "   Container Registry: $ACR_NAME"
echo "   Storage Account: $STORAGE_ACCOUNT"
echo "   OpenAI Resource: $OPENAI_RESOURCE"
echo "   Environment: $ENVIRONMENT"
echo ""
read -p "Continue with deployment? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "=========================================="
echo "PHASE 1: Azure Infrastructure Setup"
echo "=========================================="

echo ""
echo "🔧 Step 1/9: Creating resource group..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output none
echo "✅ Resource group created: $RESOURCE_GROUP"

echo ""
echo "🔧 Step 2/9: Creating Azure Storage Account..."
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --output none

# Get current identity (user or service principal) for RBAC assignment
echo "   Detecting current Azure identity..."
CURRENT_USER_ID=""
CURRENT_USER_TYPE=""

# Try to get signed-in user first
if CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null); then
    CURRENT_USER_TYPE="user"
    echo "   ✓ Detected user account: $(az ad signed-in-user show --query userPrincipalName -o tsv)"
else
    # If that fails, try to get service principal
    CURRENT_ACCOUNT=$(az account show --query user.name -o tsv)
    if [[ $CURRENT_ACCOUNT == *"@"* ]]; then
        # Still a user, but ad signed-in-user failed (may need different permissions)
        echo "   ⚠️  Could not get user object ID. Trying account lookup..."
        CURRENT_USER_ID=$(az ad user show --id "$CURRENT_ACCOUNT" --query id -o tsv 2>/dev/null || echo "")
        CURRENT_USER_TYPE="user"
    else
        # Service principal
        echo "   ✓ Detected service principal: $CURRENT_ACCOUNT"
        CURRENT_USER_ID=$(az ad sp show --id "$CURRENT_ACCOUNT" --query id -o tsv 2>/dev/null || echo "")
        CURRENT_USER_TYPE="service-principal"
    fi
fi

# Assign Storage Blob Data Contributor role to deployment identity
if [ -n "$CURRENT_USER_ID" ]; then
    echo "   Assigning Storage Blob Data Contributor role to deployment $CURRENT_USER_TYPE..."
    az role assignment create \
      --role "Storage Blob Data Contributor" \
      --assignee $CURRENT_USER_ID \
      --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
      --output none 2>/dev/null || echo "   ⚠️  Role assignment skipped (may already exist or insufficient permissions)"
else
    echo "   ⚠️  Could not determine current identity. Role assignment for deployment user skipped."
    echo "   ℹ️  The backend managed identity will still receive necessary permissions."
fi

# Create storage container using Azure AD auth
az storage container create \
  --name $STORAGE_CONTAINER \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login \
  --output none

echo "✅ Storage Account created: $STORAGE_ACCOUNT"
echo "   Container: $STORAGE_CONTAINER"
echo "   Authentication: Entra ID (Managed Identity)"

echo ""
echo "🔧 Step 3/9: Creating Azure OpenAI resource..."
echo "⚠️  Note: Azure OpenAI requires approval and may take a few minutes..."

# Check if cognitive services provider is registered
PROVIDER_STATE=$(az provider show --namespace Microsoft.CognitiveServices --query registrationState -o tsv)
if [ "$PROVIDER_STATE" != "Registered" ]; then
    echo "   Registering Microsoft.CognitiveServices provider..."
    az provider register --namespace Microsoft.CognitiveServices --wait
fi

# Create Azure OpenAI resource
az cognitiveservices account create \
  --name $OPENAI_RESOURCE \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --kind OpenAI \
  --sku S0 \
  --yes \
  --output none

# Get OpenAI key and endpoint
AZURE_OPENAI_KEY=$(az cognitiveservices account keys list \
  --name $OPENAI_RESOURCE \
  --resource-group $RESOURCE_GROUP \
  --query key1 -o tsv)

AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show \
  --name $OPENAI_RESOURCE \
  --resource-group $RESOURCE_GROUP \
  --query properties.endpoint -o tsv)

echo "✅ Azure OpenAI resource created: $OPENAI_RESOURCE"
echo "   Endpoint: $AZURE_OPENAI_ENDPOINT"

echo ""
echo "🔧 Step 4/9: Deploying GPT-4o model..."
read -p "Enter GPT-4o deployment name [e.g. gpt-4o]: " OPENAI_DEPLOYMENT
OPENAI_DEPLOYMENT=${OPENAI_DEPLOYMENT:-gpt-4o}

az cognitiveservices account deployment create \
  --name $OPENAI_RESOURCE \
  --resource-group $RESOURCE_GROUP \
  --deployment-name $OPENAI_DEPLOYMENT \
  --model-name gpt-4o \
  --model-version "2024-08-06" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name "Standard" \
  --output none

echo "✅ GPT-4o model deployed: $OPENAI_DEPLOYMENT"

echo ""
echo "=========================================="
echo "PHASE 2: Container Infrastructure"
echo "=========================================="

echo ""
echo "🔧 Step 5/9: Creating Azure Container Registry..."
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true \
  --output none
echo "✅ Container Registry created: $ACR_NAME"

echo ""
echo "🔧 Step 6/9: Building and pushing container images..."
echo "   This may take 5-10 minutes..."

echo "   Building MCP Server..."
az acr build --registry $ACR_NAME \
  --image loan-mcp:latest \
  --file src/biz_api/loan_approval/Dockerfile \
  src/biz_api/loan_approval \
  --output table

echo "   Building Backend API..."
az acr build --registry $ACR_NAME \
  --image loan-backend:latest \
  --file src/backend/Dockerfile \
  src/backend \
  --output table

echo "   Building Frontend..."
az acr build --registry $ACR_NAME \
  --image loan-frontend:latest \
  --file src/frontend/Dockerfile \
  src/frontend \
  --output table

echo "✅ All images built and pushed to ACR"

echo ""
echo "🔧 Step 7/9: Creating Container Apps environment..."
az containerapp env create \
  --name $ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --output none
echo "✅ Container Apps environment created: $ENVIRONMENT"

# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer -o tsv)

echo ""
echo "=========================================="
echo "PHASE 3: Application Deployment"
echo "=========================================="

echo ""
echo "🔧 Step 8/9: Deploying container apps..."

echo "   Deploying MCP Server..."
az containerapp create \
  --name $MCP_APP \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT \
  --image $ACR_LOGIN_SERVER/loan-mcp:latest \
  --registry-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --target-port 8070 \
  --ingress internal \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars "PROFILE=prod" \
  --output none

MCP_FQDN=$(az containerapp show --name $MCP_APP --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)
echo "   ✅ MCP Server deployed: https://$MCP_FQDN"

echo ""
echo "   Deploying Backend API with Managed Identity..."
az containerapp create \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT \
  --image $ACR_LOGIN_SERVER/loan-backend:latest \
  --registry-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 3 \
  --cpu 1.0 \
  --memory 2.0Gi \
  --system-assigned \
  --secrets \
    "azure-openai-key=$AZURE_OPENAI_KEY" \
  --env-vars \
    "PROFILE=prod" \
    "LOAN_APPROVAL_MCP_URL=https://$MCP_FQDN/mcp" \
    "AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT" \
    "AZURE_OPENAI_KEY=secretref:azure-openai-key" \
    "AZURE_OPENAI_CHAT_DEPLOYMENT_NAME=$OPENAI_DEPLOYMENT" \
    "AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT" \
    "AZURE_STORAGE_CONTAINER=$STORAGE_CONTAINER" \
    "ENABLE_OTEL=false" \
  --output none

BACKEND_FQDN=$(az containerapp show --name $BACKEND_APP --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)

# Get the managed identity principal ID
BACKEND_IDENTITY=$(az containerapp show --name $BACKEND_APP --resource-group $RESOURCE_GROUP --query identity.principalId -o tsv)

# Assign Storage Blob Data Contributor role to backend managed identity
echo "   Assigning Storage Blob Data Contributor role to backend managed identity..."
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $BACKEND_IDENTITY \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
  --output none

# Assign Cognitive Services OpenAI User role to backend managed identity
echo "   Assigning Cognitive Services OpenAI User role to backend managed identity..."
az role assignment create \
  --role "Cognitive Services OpenAI User" \
  --assignee $BACKEND_IDENTITY \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$OPENAI_RESOURCE" \
  --output none

echo "   ✅ Backend API deployed: https://$BACKEND_FQDN"
echo "   ✅ RBAC roles assigned to managed identity"

echo ""
echo "   Deploying Frontend..."
az containerapp create \
  --name $FRONTEND_APP \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT \
  --image $ACR_LOGIN_SERVER/loan-frontend:latest \
  --registry-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --target-port 80 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars \
    "VITE_API_URL=https://$BACKEND_FQDN" \
  --output none

FRONTEND_FQDN=$(az containerapp show --name $FRONTEND_APP --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)
echo "   ✅ Frontend deployed: https://$FRONTEND_FQDN"

echo ""
echo "🔧 Step 9/9: Configuring CORS for backend..."
az containerapp update \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    "CORS_ORIGINS=https://$FRONTEND_FQDN" \
  --output none
echo "✅ CORS configured"

echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "🌐 Application URLs:"
echo "   Frontend:  https://$FRONTEND_FQDN"
echo "   Backend:   https://$BACKEND_FQDN"
echo "   MCP API:   https://$MCP_FQDN"
echo ""
echo "☁️  Azure Resources:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Storage Account: $STORAGE_ACCOUNT"
echo "   OpenAI Resource: $OPENAI_RESOURCE"
echo "   Container Registry: $ACR_NAME"
echo ""
echo "💡 Tips:"
echo "   • Visit https://$FRONTEND_FQDN to use the application"
echo "   • Monitor logs: az containerapp logs show --name $BACKEND_APP -g $RESOURCE_GROUP --follow"
echo "   • View resources: az resource list -g $RESOURCE_GROUP --output table"
echo ""
echo "🗑️  To delete all resources and stop charges:"
echo "   az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""
echo "=========================================="

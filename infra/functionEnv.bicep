// Function App - Application Settings (for existing Function App)
// Uses system-assigned managed identity for:
//  - Storage (AzureWebJobsStorage)
//  - Cosmos DB NoSQL
//  - Azure OpenAI

param resourcePrefix string = 'loanprocessingagents'
param location string = 'northcentralus'

var envResourcePrefix = toLower(resourcePrefix)

// Existing Resources
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${envResourcePrefix}-fa'
}
resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: '${envResourcePrefix}-ai'
}

// Apply environment variables (merged, not overwritten)
resource functionAppSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    // App Insights (Connection String)
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString

    // Storage Accounts (System-assigned Managed Identity)
    AzureWebJobsStorage__accountName: '${envResourcePrefix}sa'
    AzureWebJobsStorage__blobServiceUri:  'https://${envResourcePrefix}sa.blob.core.windows.net'
    AzureWebJobsStorage__queueServiceUri: 'https://${envResourcePrefix}sa.queue.core.windows.net'

    // Cosmos DB (MSI-based)
    COSMOS_ACCOUNT_ENDPOINT: 'https://${envResourcePrefix}-cosmos.documents.azure.com:443/'
    COSMOS_DATABASE_NAME: 'agentdb'

    // Azure OpenAI (MSI-based)
    OPENAI_ENDPOINT: 'https://${location}.api.cognitive.microsoft.com/openai/v1/'
    OPENAI_DEPLOYMENT: 'gpt-4o'
    OPENAI_API_VERSION: '2025-01-01-preview'
  }
}

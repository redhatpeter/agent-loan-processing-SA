// Define the resource prefix (must match the main deployment)
@minLength(3)
param resourcePrefix string = 'loanprocessingagents'
var envResourcePrefix = toLower(resourcePrefix)

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${envResourcePrefix}-fa'
}

// Cosmos DB account
resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: '${envResourcePrefix}-cdb'
}

// Storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: '${envResourcePrefix}sa'
}

// Azure OpenAI account
resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: '${envResourcePrefix}-aoai'
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: '${envResourcePrefix}-ai'
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = {
  name: '${envResourcePrefix}-law'
}

// This file configures all role assignments needed for the
// Function App's system-assigned identity to securely access:
//   - Cosmos DB
//   - Storage Account
//   - Azure OpenAI
//   - Application Insights
//   - Log Analytics Workspace
// No secrets or keys are used — all auth is via Managed Identity.

// Built-in Cosmos DB Data Contributor role definition ID for this account.
var cosmosDataContributorRoleDefinitionId = '${cosmosDb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'

// Function App to Cosmos DB - Grants read/write access to Cosmos DB data
resource faCosmosDataPlaneAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(
    cosmosDb.id,
    functionApp.id,
    'fa-cosmos-nosql-data-contributor'
  )
  parent: cosmosDb
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: cosmosDataContributorRoleDefinitionId
    scope: cosmosDb.id
  }
}

// Function App to Storage Account - Grants read/write access to Storage blobs
resource faStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'fa-storage-blob')
  scope: storageAccount
  properties: {
    description: 'fa-storage-blob-role-assignment'
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    )
  }
}

// Function App to Azure OpenAI - Grants access to call GPT models using Managed Identity
resource faOpenAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'fa-openai')
  scope: openAi
  properties: {
    description: 'fa-openai-role-assignment'
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services User
    )
  }
}

// Function App to Application Insights - Grants permission to publish metrics via Managed Identity
resource faMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'fa-metrics')
  scope: appInsights
  properties: {
    description: 'fa-metrics-role-assignment'
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '3913510d-42f4-4e42-8a64-420c390055eb' // Monitoring Metrics Publisher
    )
  }
}

// Function App to Log Analytics Workspace - Grants access to ingest or read logs for diagnostics
resource faLogAnalyticsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'fa-law')
  scope: logAnalytics
  properties: {
    description: 'fa-law-role-assignment'
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '73c42c96-874c-492b-b04d-ab87d138a893' // Log Analytics Reader
    )
  }
}

output functionAppPrincipalId string = functionApp.identity.principalId
output cosmosDbId string = cosmosDb.id
output storageAccountId string = storageAccount.id

// Define the location for all resources
@description('The Azure region to deploy resources into')
param location string = 'northcentralus'

// Parameter to control whether the GPT-4o model should be deployed
@description('Deploy gpt-4o model - set to true if not deployed yet')
param deployGpt4oModel bool = false

// Prefix for naming all resources
@description('A prefix for all resources deployed')
param resourcePrefix string = 'loanprocessingagents'
var envResourcePrefix = toLower(resourcePrefix)

// Deploy a storage account
module storageAccount 'br/public:avm/res/storage/storage-account:0.29.0' = {
  name: 'storageAccountDeployment'
  params: {
    name: '${envResourcePrefix}sa'
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
  }
}

// Deploy a Log Analytics Workspace
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'logAnalyticsWorkspaceDeployment'
  params: {
    name: '${envResourcePrefix}-law'
    location: location
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }    
  }
}

// Deploy Application Insights linked to the Log Analytics Workspace
module appInsights 'br/public:avm/res/insights/component:0.7.0' = {
  name: 'appInsightsDeployment'
  params: {
    name: '${envResourcePrefix}-ai'
    location: location
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
  }
}

// Deploy an App Service Plan (Server Farm) for the Function App
module serverfarm 'br/public:avm/res/web/serverfarm:0.5.0' = {
  name: 'serverfarmDeployment'
  params: {
    name: '${envResourcePrefix}-sf'
    location: location
    skuName: 'S1'
    skuCapacity: 1
    reserved: true
    zoneRedundant: false
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
  }
}

// Deploy the Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${envResourcePrefix}-fa'
  location: location
  kind: 'functionapp,linux' // Specifies that this is a Linux-based Function App
  identity: {
    type: 'SystemAssigned' // Enables a system-assigned managed identity
  }
  properties: {
    serverFarmId: serverfarm.outputs.resourceId // Links the Function App to the App Service Plan
    httpsOnly: true // Enforces HTTPS-only connections
    siteConfig: {
      alwaysOn: true // Keeps the Function App always running
      linuxFxVersion: 'Python|3.11' // Specifies the runtime stack and version
    }
  }
}

// Deploy an Azure OpenAI resource
resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: '${envResourcePrefix}-aoai'
  location: location
  kind: 'OpenAI' // Specifies the resource type as OpenAI
  sku: {
    name: 'S0' // Specifies the pricing tier
  }
  properties: {
    publicNetworkAccess: 'Enabled' // Allows public network access
  }
  tags: {
    Environment: 'Non-Prod'
    Project: 'Loan Processing Agents'
  }
}

// Conditionally deploy the GPT-4o model if the parameter is set to true
resource gpt4o 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployGpt4oModel) {
  parent: openAi // Links the deployment to the OpenAI resource
  name: 'gpt-4o'
  sku: {
    name: 'GlobalStandard'
    capacity: 450 // Specifies the capacity for the deployment
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-08-06' // Specifies the model version
    }
  }
}

// Deploy a Cosmos DB account
module cosmosDb 'br/public:avm/res/document-db/database-account:0.18.0' = {
  name: 'cosmosDbDeployment'
  params: {
    name: '${envResourcePrefix}-cdb'
    location: location
    failoverLocations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    defaultConsistencyLevel: 'Session' // Specifies the consistency level
    enableFreeTier: false
    enableAnalyticalStorage: false
    sqlDatabases: [
      {
        name: 'agentdb'
        autoscaleSettingsMaxThroughput: 4000 // Specifies the maximum throughput for autoscale
      }
    ]
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
  }
}


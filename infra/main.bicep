param location string = 'northcentralus'

@description('Deploy gpt-4o model - set to true if not deployed yet')
param deployGpt4oModel bool = false

@description('A prefix for all resources deployed')
param resourcePrefix string = 'loanprocessingagents'
var envResourcePrefix = toLower(resourcePrefix)

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

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${envResourcePrefix}-fa'
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: serverfarm.outputs.resourceId
    httpsOnly: true
    siteConfig: {
      alwaysOn: true
      linuxFxVersion: 'Python|3.11'
    }
  }
}

resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: '${envResourcePrefix}-aoai'
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    Environment: 'Non-Prod'
    Project: 'Loan Processing Agents'
  }
}

resource gpt4o 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployGpt4oModel) {
  parent: openAi
  name: 'gpt-4o'
  sku: {
    name: 'GlobalStandard'
    capacity: 450
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-08-06'
    }
  }
}

module cosmosDb 'br/public:avm/res/document-db/database-account:0.18.0' = {
  name: 'cosmosDbDeployment'
  params: {
    name: '${envResourcePrefix}-cosmos'
    location: location
    failoverLocations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    defaultConsistencyLevel: 'Session'
    enableFreeTier: false
    enableAnalyticalStorage: false
    sqlDatabases: [
      {
        name: 'agentdb'
        autoscaleSettingsMaxThroughput: 4000
      }
    ]
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
  }
}


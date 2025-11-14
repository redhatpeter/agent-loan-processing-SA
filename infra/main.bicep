param location string = resourceGroup().location

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
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    location: location
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
    reserved: true
    skuName: 'FC1'
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
    zoneRedundant: false
  }
}

module functionApp 'br/public:avm/res/web/site:0.19.4' = {
  name: 'functionAppDeployment'
  params: {
    kind: 'functionapp'
    name: '${envResourcePrefix}-fa'
    location: location
    serverFarmResourceId: serverfarm.outputs.resourceId
    httpsOnly: true
    managedIdentities: {
      systemAssigned: true
    }
    siteConfig: {
      alwaysOn: false
    }
    functionAppConfig: {
      runtime: {
        name: 'python'
        version: '3.11'
      }
      deployment: {
        storage: {
            type: 'BlobContainer'
            value: storageAccount.outputs.resourceId
            authentication: {
              type: 'SystemAssignedIdentity'
            }
          }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 100
      }
    }
    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
  }
}

module aiFoundry 'br/public:avm/ptn/ai-ml/ai-foundry:0.6.0' = {
  name: 'aiFoundryDeployment'
  params: {
    baseName: 'lpagents-aif' 
    location: location

    storageAccountConfiguration: {
      existingResourceId: storageAccount.outputs.resourceId
    }

    aiFoundryConfiguration: {
      accountName: '${envResourcePrefix}-aif'
      location: location
      sku: 'S0'
    }

    tags: {
      Environment: 'Non-Prod'
      Project: 'Loan Processing Agents'
    }
  }
}

resource aifProject 'Microsoft.CognitiveServices/accounts/projects@2025-07-01-preview' = {
  name: '${envResourcePrefix}-aif/loanprocessingagents-proj'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Loan Processing Agents Project'
    description: 'Project for managing loan processing agents using AI Foundry'
  }
  tags: {
    Environment: 'Non-Prod'
    Project: 'Loan Processing Agents'
  }
}


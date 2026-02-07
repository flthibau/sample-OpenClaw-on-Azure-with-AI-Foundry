using './main.bicep'

// ===========================================================
// OpenClaw on Azure with AI Foundry - Parameters
// ===========================================================

// Deployment location
param location = 'eastus2'

// Resource naming
param baseName = 'openclaw'
param environment = 'dev'

// VM Configuration
param vmSize = 'Standard_D2s_v5'

// Authentication (set via command line or parameter overrides)
param adminUsername = 'azureuser'
// param adminPassword = '' // Provide at deployment time

// Azure Bastion
param enableBastion = true

// Azure AI Foundry (optional - can be configured post-deployment)
param aiFoundryEndpoint = ''

// Auto-shutdown configuration
param enableAutoShutdown = true
param autoShutdownTime = '19:00'

// Resource tags
param tags = {
  project: 'OpenClaw'
  environment: 'dev'
  deployedBy: 'Bicep'
  repository: 'sample-OpenClaw-on-Azure-with-AI-Foundry'
}

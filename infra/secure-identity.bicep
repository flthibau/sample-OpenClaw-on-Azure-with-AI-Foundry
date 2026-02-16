// =============================================================================
// secure-identity.bicep — UAMI + Key Vault + RBAC for OpenClaw zero-secret arch
// =============================================================================
//
// Deploys:
//   1. User-Assigned Managed Identity (UAMI)
//   2. Azure Key Vault with RBAC authorization
//   3. RBAC role assignments (least privilege)
//
// Cross-RG role (Cognitive Services) is assigned via az CLI after deployment.
//
// Usage:
//   az deployment group create \
//     --resource-group rg-openclaw-test \
//     --template-file secure-identity.bicep \
//     --parameters storageAccountName=stopenclawmedia
// =============================================================================

@description('Azure region')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'openclaw'

@description('Existing Storage Account name')
param storageAccountName string = 'stopenclawmedia'

@description('Tags')
param tags object = {
  project: 'OpenClaw'
  component: 'secure-identity'
  managedBy: 'Bicep'
}

// =============================================================================
// Variables
// =============================================================================

var identityName = 'id-${baseName}'
var keyVaultName = 'kv-${baseName}-8iei'

// Built-in RBAC role definition IDs
var roles = {
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
}

// =============================================================================
// 1. User-Assigned Managed Identity
// =============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// =============================================================================
// 2. Key Vault (RBAC authorization mode)
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// =============================================================================
// 3. RBAC Role Assignments (same RG)
// =============================================================================

// 3a. UAMI → Key Vault Secrets User
resource kvSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, roles.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// 3b. UAMI → Storage Blob Data Contributor
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource storageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, roles.storageBlobDataContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// 3c. UAMI → Reader on Resource Group
resource rgReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, roles.reader)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.reader)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// NOTE: Cognitive Services User role on rg-admin-0508 is assigned via az CLI:
//   az role assignment create --assignee <UAMI-principalId> \
//     --role "Cognitive Services User" \
//     --scope /subscriptions/.../resourceGroups/rg-admin-0508/providers/Microsoft.CognitiveServices/accounts/admin-0508-resource

// =============================================================================
// Outputs
// =============================================================================

output managedIdentityName string = managedIdentity.name
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri

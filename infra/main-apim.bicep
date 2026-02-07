// =====================================================
// OpenClaw on Azure with AI Foundry + APIM
// Infrastructure with API Management for keyless auth
// =====================================================

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
@minLength(3)
@maxLength(15)
param baseName string = 'openclaw'

@description('Administrator username for the VM')
@secure()
param adminUsername string

@description('Administrator password for the VM')
@secure()
param adminPassword string

@description('VM size for OpenClaw workload')
param vmSize string = 'Standard_D2s_v5'

@description('Auto-shutdown time in HH:mm format (24-hour, UTC)')
param autoShutdownTime string = '19:00'

@description('Enable auto-shutdown')
param enableAutoShutdown bool = true

@description('GPT model to deploy (gpt-5.2-codex, gpt-5.2, gpt-4o)')
param modelName string = 'gpt-5.2-codex'

@description('Model version')
param modelVersion string = '2026-01-01'

@description('Publisher email for APIM')
param publisherEmail string = 'admin@contoso.com'

@description('Bing Search API Key (optional - for future use)')
@secure()
#disable-next-line no-unused-params
param bingSearchApiKey string = ''

@description('Tags for all resources')
param tags object = {
  project: 'OpenClaw'
  deployedBy: 'Bicep'
}

// =====================================================
// Variables
// =====================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var vnetName = 'vnet-${baseName}'
var vmName = 'vm-${baseName}'
var bastionName = 'bastion-${baseName}'
var nsgName = 'nsg-${baseName}'
var aiName = 'ai-${baseName}-${uniqueSuffix}'
var apimName = 'apim-${baseName}-${uniqueSuffix}'

// Network configuration
var vnetAddressPrefix = '10.0.0.0/16'
var defaultSubnetPrefix = '10.0.0.0/24'
var bastionSubnetPrefix = '10.0.1.0/26'

// =====================================================
// Network Security Group (no SSH from internet)
// =====================================================

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'DenySSHFromInternet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Deny'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Deny SSH from Internet - use Bastion only'
        }
      }
      {
        name: 'AllowHTTPSOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// Bastion NSG for AzureBastionSubnet
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-bastion-${baseName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionHostCommunication'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [ '8080', '5701' ]
        }
      }
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [ '22', '3389' ]
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionCommunication'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [ '8080', '5701' ]
        }
      }
      {
        name: 'AllowHttpOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

// =====================================================
// Virtual Network
// =====================================================

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: defaultSubnetPrefix
          networkSecurityGroup: { id: nsg.id }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: { id: bastionNsg.id }
        }
      }
    ]
  }
}

// =====================================================
// Bastion Public IP
// =====================================================

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-${bastionName}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// =====================================================
// Azure Bastion
// =====================================================

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: { id: vnet.properties.subnets[1].id }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
}

// =====================================================
// Network Interface (no public IP)
// =====================================================

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: 'nic-${vmName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// =====================================================
// Azure AI Foundry (Cognitive Services OpenAI)
// =====================================================

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: aiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: aiName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true  // Force Entra ID auth
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Deploy GPT model
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: modelName
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
  sku: {
    name: 'Standard'
    capacity: 10
  }
}

// =====================================================
// API Management (Consumption tier for cost savings)
// =====================================================

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: 'OpenClaw Admin'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Grant APIM access to AI Foundry
resource apimAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(apim.id, aiFoundry.id, 'Cognitive Services OpenAI User')
  scope: aiFoundry
  properties: {
    principalId: apim.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalType: 'ServicePrincipal'
  }
}

// Create API for OpenAI proxy
resource openaiApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'openai-proxy'
  properties: {
    displayName: 'Azure OpenAI Proxy'
    path: 'openai'
    protocols: [ 'https' ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    serviceUrl: '${aiFoundry.properties.endpoint}openai'
  }
}

// Policy to transform subscription key to Managed Identity token
resource openaiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: openaiApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-header name="api-key" exists-action="delete" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" ignore-error="false" />
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// Create catch-all operation for all OpenAI endpoints
resource openaiApiOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openaiApi
  name: 'all-operations'
  properties: {
    displayName: 'All OpenAI Operations'
    method: '*'
    urlTemplate: '/*'
  }
}

// Create subscription for OpenClaw
resource openclawSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'openclaw-subscription'
  properties: {
    displayName: 'OpenClaw Subscription'
    scope: '/apis/${openaiApi.name}'
    state: 'active'
    allowTracing: false
  }
}

// =====================================================
// Virtual Machine with OpenClaw
// =====================================================

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 128
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(cloudInitScript)
    }
    networkProfile: {
      networkInterfaces: [ { id: nic.id } ]
    }
  }
}

// Auto-shutdown schedule
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (enableAutoShutdown) {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: replace(autoShutdownTime, ':', '') }
    timeZoneId: 'UTC'
    targetResourceId: vm.id
  }
}

// =====================================================
// Cloud-init script for native OpenClaw installation
// =====================================================

var cloudInitScript = '''#cloud-config
package_update: true
package_upgrade: true

packages:
  - curl
  - git
  - jq

write_files:
  - path: /home/${adminUsername}/install-openclaw.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      
      echo "📦 Installing Node.js 22..."
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y nodejs
      
      echo "🦞 Installing OpenClaw..."
      sudo npm install -g openclaw@latest
      
      echo "📁 Creating OpenClaw directories..."
      mkdir -p ~/.openclaw
      mkdir -p ~/.openclaw/workspace
      mkdir -p ~/.openclaw/credentials
      
      echo "✅ OpenClaw installed successfully!"
      openclaw --version

  - path: /home/${adminUsername}/configure-openclaw.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      
      APIM_ENDPOINT="$1"
      APIM_KEY="$2"
      BING_API_KEY="$3"
      
      echo "⚙️ Configuring OpenClaw..."
      
      cat > ~/.openclaw/openclaw.json << 'CONFIGEOF'
      {
        "agents": {
          "defaults": {
            "model": {
              "primary": "azure-openai/gpt-5.2-codex",
              "fallbacks": ["azure-openai/gpt-5.2", "azure-openai/gpt-4o"]
            },
            "models": {
              "azure-openai/gpt-5.2-codex": { "alias": "Codex 5.2" },
              "azure-openai/gpt-5.2": { "alias": "GPT-5.2" },
              "azure-openai/gpt-4o": { "alias": "GPT-4o" }
            }
          }
        },
        "models": {
          "mode": "merge",
          "providers": {
            "azure-openai": {
              "baseUrl": "APIM_ENDPOINT_PLACEHOLDER/openai",
              "apiKey": "APIM_KEY_PLACEHOLDER",
              "api": "openai-completions",
              "models": [
                { "id": "gpt-5.2-codex", "name": "GPT-5.2 Codex", "reasoning": true },
                { "id": "gpt-5.2", "name": "GPT-5.2", "reasoning": true },
                { "id": "gpt-4o", "name": "GPT-4o" }
              ]
            }
          }
        },
        "gateway": {
          "bind": "loopback",
          "port": 18789,
          "auth": {
            "mode": "password"
          }
        }
      }
      CONFIGEOF
      
      # Replace placeholders
      sed -i "s|APIM_ENDPOINT_PLACEHOLDER|$APIM_ENDPOINT|g" ~/.openclaw/openclaw.json
      sed -i "s|APIM_KEY_PLACEHOLDER|$APIM_KEY|g" ~/.openclaw/openclaw.json
      
      # Add Bing Search if provided
      if [ -n "$BING_API_KEY" ]; then
        echo "🔍 Configuring Bing Search..."
        # Note: OpenClaw uses Brave/Perplexity, so we'd need a custom tool
        # For now we'll document this as a future enhancement
      fi
      
      echo "✅ OpenClaw configured!"

  - path: /home/${adminUsername}/start.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "🦞 Starting OpenClaw Gateway..."
      openclaw gateway --port 18789 &
      echo "Gateway started on port 18789"
      echo "Access the dashboard at http://localhost:18789/"

  - path: /home/${adminUsername}/stop.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "🛑 Stopping OpenClaw Gateway..."
      pkill -f "openclaw gateway" || true
      echo "Gateway stopped"

  - path: /home/${adminUsername}/status.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "📊 OpenClaw Status"
      echo "=================="
      openclaw gateway status 2>/dev/null || echo "Gateway not running"
      echo ""
      echo "Health check:"
      openclaw health 2>/dev/null || echo "Unable to check health"

  - path: /home/${adminUsername}/logs.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      openclaw logs --follow

  - path: /etc/motd
    permissions: '0644'
    content: |
      ╔═══════════════════════════════════════════════════════════════╗
      ║              🦞 OpenClaw on Azure 🦞                          ║
      ║                                                               ║
      ║  Your AI assistant is ready!                                  ║
      ║                                                               ║
      ║  Quick commands:                                              ║
      ║    ./start.sh          - Start OpenClaw Gateway               ║
      ║    ./stop.sh           - Stop OpenClaw Gateway                ║
      ║    ./status.sh         - Check status                         ║
      ║    ./logs.sh           - View logs                            ║
      ║                                                               ║
      ║  Run the onboarding wizard:                                   ║
      ║    openclaw onboard                                           ║
      ║                                                               ║
      ║  Dashboard: http://localhost:18789/                           ║
      ╚═══════════════════════════════════════════════════════════════╝

runcmd:
  - chown -R ${adminUsername}:${adminUsername} /home/${adminUsername}/
  - su - ${adminUsername} -c '/home/${adminUsername}/install-openclaw.sh'

final_message: "OpenClaw installation complete!"
'''

// =====================================================
// Outputs
// =====================================================

output vmName string = vm.name
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output bastionName string = bastion.name
output aiFoundryEndpoint string = aiFoundry.properties.endpoint
output aiFoundryName string = aiFoundry.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimName string = apim.name
output subscriptionId string = openclawSubscription.name
output modelDeploymentName string = modelDeployment.name

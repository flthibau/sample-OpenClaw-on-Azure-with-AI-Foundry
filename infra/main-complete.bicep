/*
  OpenClaw on Azure - Complete Infrastructure
  Includes: VM, VNet, Bastion, Azure OpenAI, Role Assignments
  Fully automated - no manual steps required
*/

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'openclaw'

@description('Environment (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('VM administrator username')
param vmAdminUsername string = 'azureuser'

@secure()
@description('VM administrator password')
param vmAdminPassword string

@description('VM size')
param vmSize string = 'Standard_D2s_v5'

@description('Enable auto-shutdown at specified time (UTC)')
param autoShutdownTime string = '1900'

@description('Enable Azure Bastion')
param enableBastion bool = true

@description('Azure OpenAI model to deploy')
@allowed(['gpt-4o', 'gpt-4o-mini', 'gpt-35-turbo'])
param aiModel string = 'gpt-4o'

@description('Model version')
param aiModelVersion string = '2024-08-06'

@description('Tokens per minute for the AI model (x1000)')
param aiModelCapacity int = 10

// ============================================================================
// Variables
// ============================================================================

var resourceSuffix = '${baseName}-${environment}'
var vnetName = 'vnet-${resourceSuffix}'
var nsgName = 'nsg-${resourceSuffix}'
var vmName = 'vm-${resourceSuffix}'
var nicName = 'nic-${resourceSuffix}'
var bastionName = 'bastion-${resourceSuffix}'
var bastionPipName = 'pip-bastion-${resourceSuffix}'
var managedIdentityName = 'id-${resourceSuffix}'
var aiFoundryName = 'ai-${resourceSuffix}'
var aiDeploymentName = '${aiModel}-deployment'

var vnetAddressPrefix = '10.0.0.0/16'
var defaultSubnetPrefix = '10.0.0.0/24'
var bastionSubnetPrefix = '10.0.1.0/26'

// Cloud-init script with AI Foundry configuration embedded
var cloudInitScript = '''
#cloud-config
package_update: true
package_upgrade: true

packages:
  - git
  - curl
  - jq
  - unzip

runcmd:
  # Install Node.js 20.x
  - curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  - apt-get install -y nodejs
  
  # Install pnpm
  - npm install -g pnpm
  
  # Install Azure CLI
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  
  # Clone OpenClaw
  - git clone https://github.com/openclaw/openclaw.git /opt/openclaw
  - chown -R ${VM_ADMIN_USERNAME}:${VM_ADMIN_USERNAME} /opt/openclaw
  
  # Install dependencies
  - cd /opt/openclaw && pnpm install
  
  # Create OpenClaw configuration
  - |
    cat > /opt/openclaw/.env << 'ENVEOF'
    # Azure AI Foundry Configuration (Auto-configured)
    AZURE_USE_MANAGED_IDENTITY=true
    AZURE_OPENAI_ENDPOINT=${AI_ENDPOINT}
    AZURE_OPENAI_DEPLOYMENT=${AI_DEPLOYMENT}
    AZURE_OPENAI_API_VERSION=2024-10-01-preview
    
    # OpenClaw Settings
    APP_NAME=OpenClaw
    LOG_LEVEL=info
    PORT=18789
    
    # Security
    SESSION_SECRET=${SESSION_SECRET}
    ENVEOF
  - chown ${VM_ADMIN_USERNAME}:${VM_ADMIN_USERNAME} /opt/openclaw/.env
  
  # Create systemd service
  - |
    cat > /etc/systemd/system/openclaw.service << 'SVCEOF'
    [Unit]
    Description=OpenClaw Gateway Service
    After=network.target

    [Service]
    Type=simple
    User=${VM_ADMIN_USERNAME}
    WorkingDirectory=/opt/openclaw
    EnvironmentFile=/opt/openclaw/.env
    ExecStart=/usr/bin/npx openclaw gateway start
    Restart=on-failure
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    SVCEOF
  - systemctl daemon-reload
  - systemctl enable openclaw
  
  # Create start script
  - |
    cat > /opt/openclaw/start.sh << 'STARTEOF'
    #!/bin/bash
    cd /opt/openclaw
    echo "🚀 Starting OpenClaw..."
    sudo systemctl start openclaw
    echo "✅ OpenClaw started! Access via port 18789"
    journalctl -u openclaw -f
    STARTEOF
  - chmod +x /opt/openclaw/start.sh
  - chown ${VM_ADMIN_USERNAME}:${VM_ADMIN_USERNAME} /opt/openclaw/start.sh
  
  # Create status script
  - |
    cat > /opt/openclaw/status.sh << 'STATUSEOF'
    #!/bin/bash
    echo "📊 OpenClaw Status"
    echo "=================="
    systemctl status openclaw --no-pager
    echo ""
    echo "🔍 Testing Azure AI Foundry connection..."
    TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://cognitiveservices.azure.com/' -H 'Metadata: true' | jq -r '.access_token')
    if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
      echo "✅ Managed Identity token obtained successfully"
    else
      echo "❌ Failed to get Managed Identity token"
    fi
    STATUSEOF
  - chmod +x /opt/openclaw/status.sh
  - chown ${VM_ADMIN_USERNAME}:${VM_ADMIN_USERNAME} /opt/openclaw/status.sh
  
  # Create symlinks in user home
  - ln -sf /opt/openclaw /home/${VM_ADMIN_USERNAME}/openclaw
  - ln -sf /opt/openclaw/start.sh /home/${VM_ADMIN_USERNAME}/start.sh
  - ln -sf /opt/openclaw/status.sh /home/${VM_ADMIN_USERNAME}/status.sh
  
  # Custom MOTD
  - |
    cat > /etc/motd << 'MOTDEOF'
    
    ╔═══════════════════════════════════════════════════════════════╗
    ║                  🤖 OpenClaw on Azure 🤖                       ║
    ║                                                               ║
    ║  ✅ Fully configured and ready to use!                       ║
    ║                                                               ║
    ║  Quick commands:                                              ║
    ║    ./start.sh   - Start OpenClaw                             ║
    ║    ./status.sh  - Check status & AI connection               ║
    ║    cd ~/openclaw - Go to OpenClaw directory                  ║
    ║                                                               ║
    ║  AI Model: ${AI_MODEL} (Azure AI Foundry)                    ║
    ║  Authentication: Managed Identity (no keys needed!)          ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
    
    MOTDEOF
  
  # Start OpenClaw automatically
  - systemctl start openclaw

final_message: "OpenClaw deployment complete! Connect via Azure Bastion to get started."
'''

// Generate a random session secret
var sessionSecret = uniqueString(resourceGroup().id, deployment().name, 'session')

// Replace placeholders in cloud-init
var cloudInitFinal = replace(
  replace(
    replace(
      replace(
        replace(cloudInitScript, '\${VM_ADMIN_USERNAME}', vmAdminUsername),
        '\${AI_ENDPOINT}', 'https://${aiFoundryName}.openai.azure.com/'),
      '\${AI_DEPLOYMENT}', aiDeploymentName),
    '\${SESSION_SECRET}', sessionSecret),
  '\${AI_MODEL}', aiModel)

// ============================================================================
// User Assigned Managed Identity
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: {
    project: baseName
    environment: environment
  }
}

// ============================================================================
// Azure OpenAI (AI Foundry)
// ============================================================================

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: aiFoundryName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: aiFoundryName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  tags: {
    project: baseName
    environment: environment
  }
}

resource aiModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: aiFoundry
  name: aiDeploymentName
  sku: {
    name: 'Standard'
    capacity: aiModelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: aiModel
      version: aiModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
}

// Role assignment: Managed Identity -> Cognitive Services OpenAI User
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundry.id, managedIdentity.id, 'Cognitive Services OpenAI User')
  scope: aiFoundry
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
  }
}

// ============================================================================
// Network Security Group
// ============================================================================

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
  tags: {
    project: baseName
    environment: environment
  }
}

resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = if (enableBastion) {
  name: 'nsg-bastion-${resourceSuffix}'
  location: location
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
          destinationPortRanges: ['8080', '5701']
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
          destinationPortRanges: ['22', '3389']
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
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowHttpOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]
  }
  tags: {
    project: baseName
    environment: environment
  }
}

// ============================================================================
// Virtual Network
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: defaultSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: enableBastion ? {
            id: bastionNsg.id
          } : null
        }
      }
    ]
  }
  tags: {
    project: baseName
    environment: environment
  }
}

// ============================================================================
// Network Interface
// ============================================================================

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
  tags: {
    project: baseName
    environment: environment
  }
}

// ============================================================================
// Virtual Machine
// ============================================================================

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
      customData: base64(cloudInitFinal)
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
  tags: {
    project: baseName
    environment: environment
  }
}

// Auto-shutdown schedule
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: 'UTC'
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
  tags: {
    project: baseName
    environment: environment
  }
}

// ============================================================================
// Azure Bastion
// ============================================================================

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (enableBastion) {
  name: bastionPipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  tags: {
    project: baseName
    environment: environment
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = if (enableBastion) {
  name: bastionName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    enableFileCopy: true
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: {
            id: bastionPip.id
          }
          subnet: {
            id: vnet.properties.subnets[1].id
          }
        }
      }
    ]
  }
  tags: {
    project: baseName
    environment: environment
  }
}

// ============================================================================
// Outputs
// ============================================================================

output vmName string = vm.name
output vmResourceId string = vm.id
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output bastionName string = enableBastion ? bastion.name : 'Not deployed'
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId
output aiFoundryName string = aiFoundry.name
output aiFoundryEndpoint string = 'https://${aiFoundry.name}.openai.azure.com/'
output aiModelDeployment string = aiModelDeployment.name
output connectionInstructions string = 'Connect via Azure Portal > VM > Connect > Bastion. OpenClaw is pre-configured and running!'

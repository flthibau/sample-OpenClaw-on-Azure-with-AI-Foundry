// =====================================================
// OpenClaw on Azure with AI Foundry
// Main Infrastructure Template
// =====================================================

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
@minLength(3)
@maxLength(20)
param baseName string = 'openclaw'

@description('Environment name (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Administrator username for the VM')
@secure()
param adminUsername string

@description('Administrator password for the VM')
@secure()
param adminPassword string

@description('VM size for OpenClaw workload')
param vmSize string = 'Standard_D2s_v5'

@description('Enable Azure Bastion for secure access')
param enableBastion bool = true

@description('Azure AI Foundry endpoint URL')
param aiFoundryEndpoint string = ''

@description('Auto-shutdown time in HH:mm format (24-hour, UTC)')
param autoShutdownTime string = '19:00'

@description('Enable auto-shutdown')
param enableAutoShutdown bool = true

@description('Tags for all resources')
param tags object = {
  project: 'OpenClaw'
  environment: environment
  deployedBy: 'Bicep'
}

// =====================================================
// Variables
// =====================================================

var resourcePrefix = '${baseName}-${environment}'
var vnetName = 'vnet-${resourcePrefix}'
var vmName = 'vm-${resourcePrefix}'
var bastionName = 'bastion-${resourcePrefix}'
var nsgName = 'nsg-${resourcePrefix}'
var identityName = 'id-${resourcePrefix}'

// Network configuration
var vnetAddressPrefix = '10.0.0.0/16'
var defaultSubnetPrefix = '10.0.0.0/24'
var bastionSubnetPrefix = '10.0.1.0/26'

// =====================================================
// User Assigned Managed Identity
// =====================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// =====================================================
// Network Security Group
// =====================================================

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  tags: tags
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
          description: 'Deny all inbound traffic by default'
        }
      }
    ]
  }
}

// Bastion NSG for AzureBastionSubnet
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = if (enableBastion) {
  name: 'nsg-bastion-${resourcePrefix}'
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
          destinationPortRanges: [
            '8080'
            '5701'
          ]
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
          destinationPortRanges: [
            '22'
            '3389'
          ]
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
          destinationPortRanges: [
            '8080'
            '5701'
          ]
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
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: defaultSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
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
}

// =====================================================
// Network Interface
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
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// =====================================================
// Virtual Machine
// =====================================================

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
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
      computerName: take(replace(vmName, '-', ''), 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: {
            rebootSetting: 'IfRequired'
          }
        }
      }
      customData: base64(loadTextContent('cloud-init.yaml'))
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
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        diskSizeGB: 128
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// =====================================================
// Auto-shutdown Schedule
// =====================================================

resource autoShutdownSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = if (enableAutoShutdown) {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: replace(autoShutdownTime, ':', '')
    }
    timeZoneId: 'UTC'
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// =====================================================
// Azure Bastion
// =====================================================

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (enableBastion) {
  name: 'pip-${bastionName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
}

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = if (enableBastion) {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    scaleUnits: 2
    enableTunneling: true
    enableFileCopy: true
    enableIpConnect: true
    disableCopyPaste: false
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

// =====================================================
// Outputs
// =====================================================

@description('The name of the deployed VM')
output vmName string = vm.name

@description('The resource ID of the VM')
output vmResourceId string = vm.id

@description('The private IP address of the VM')
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress

@description('The name of the Azure Bastion')
output bastionName string = enableBastion ? bastion.name : 'Not deployed'

@description('The Managed Identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The Managed Identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Connection instructions')
output connectionInstructions string = 'Connect to your VM via Azure Portal > ${vm.name} > Connect > Bastion'

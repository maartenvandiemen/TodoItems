// The virtual machine for the build agent (a self-hosted runner), in the workload subnet of the agent spoke.
// Deploy into the resource group of that spoke. Called by main.bicep.
//
// The VM has NO public IP address and nothing is allowed in from the internet: it makes its own connection out to
// GitHub or Azure DevOps (through the hub firewall), and reaches the private endpoints of the application through the
// firewall too. To work on it, connect through Azure Bastion (the Developer SKU is free: Connect > Bastion on the VM
// in the portal, with user and password), or use 'az vm run-command invoke' (no network path needed).
//
// The runner itself is NOT installed here: it has to register with a token that expires after an hour.

param location string

@description('Resource id of the subnet (the workload subnet of the agent spoke).')
param subnetId string

param adminUsername string = 'azureuser'

@description('Password of the administrator.')
@secure()
param adminPassword string

param vmSize string = 'Standard_B2s'

var vmName = 'vm-build-agent'

resource nic 'Microsoft.Network/networkInterfaces@2026-03-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      // Ubuntu Server 26.04 LTS, x64, generation 2.
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-26_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        // Sign in with the password (through Bastion): there is no public address to attack.
        disablePasswordAuthentication: false
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
  }
}

output vmName string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress

 Param
    (
        [Parameter(Mandatory = $true)] [string] $SubscriptionId,
        [Parameter(Mandatory = $true)] [string] $Resourcegroup,
        [Parameter(Mandatory = $true)] [string] $WebsiteName
    )      
      
      $token = Get-AzAccessToken
      $authHeader = @{
          'Content-Type'='application/json'
          'Authorization'='Bearer ' + $token.Token
      }
      $locations = @(
        # Europe
        "westeurope", "northeurope", "francesouth", "francecentral", "ukwest", "uksouth", "germanywestcentral", "norwayeast", "swedencentral", "switzerlandnorth",
        # Americas
        "brazilsouth", "canadacentral", "centralus", "eastus", "eastus2", "southcentralus", "westus2", "westus3",
        # Middle East
        "qatarcentral", "uaenorth",
        # Africa
        "southafricanorth",
        # Asia Pacific
        "australiaeast", "centralindia", "japaneast", "koreacentral", "southeastasia", "eastasia"
      )
      $locations | foreach-Object {
          $restUrl = "https://$_.management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$Resourcegroup/providers/Microsoft.Web/sites/"+$WebsiteName+"?api-version=2022-03-01";
          Write-Host $restUrl
          Invoke-RestMethod -Uri $restUrl -Method Get -Headers $authHeader
      }

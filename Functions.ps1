Function Get-ExternalIP {
    #Get the external IP from where the script is running
    return "error"#$(Invoke-WebRequest -uri "https://api.ipify.org/" -UseBasicParsing).Content
}

Function Get-Product {
    [CmdletBinding()]
    param(
        [string]$product
    )
    #Check for the existence of a product
    return  Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -match $product}
}

Function Wait-VM {
    [CmdletBinding()]
    param(
        [string]$ipAddress
    )
    Start-Sleep -Seconds 60
    do {
        $pingTest = $(Test-NetConnection -ComputerName $ipAddress -InformationLevel Quiet -WarningAction SilentlyContinue)
        Start-Sleep -Seconds 30
        Write-Host "Waiting for 30 seconds"
    } until ($pingTest -eq "True")
}

Function Restart-VM {
    [CmdletBinding()]
    param(
        $session
    )
    Write-Host "Rebooting VM"
    Invoke-Command -Session $session -ScriptBlock {
        Restart-Computer -Force
    }
}

Function Create-PSSession {
    [CmdletBinding()]
    param(
        $ipAddress,
        $username,
        $password
    )
    [securestring]$secStringPassword = ConvertTo-SecureString $password -AsPlainText -Force
    [pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($username, $secStringPassword)
    return New-PSSession -ComputerName $($tfOutputs.public_ip_address.value) -Credential $credObject -Authentication Basic
}

Function Create-CimSession {
    [CmdletBinding()]
    param(
        $ipAddress,
        $username,
        $password
    )
    [securestring]$secStringPassword = ConvertTo-SecureString $password -AsPlainText -Force
    [pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($username, $secStringPassword)
    return New-CimSession -ComputerName $($tfOutputs.public_ip_address.value) -Credential $credObject -Authentication Basic
}

Function Get-VMPowerState {
    param (
        $rg,
        $vmName
    )
    try {
        $powerState = az vm show --resource-group $rg --name $vmName --show-details | ConvertFrom-Json | Select-Object -ExpandProperty PowerState
        return $powerState
    } catch {
        Throw "Could not get the powerstate of the VM"
    }
}

Function Deallocate-VM {
    param (
        $rg,
        $vmName
    )
    try {
        az vm deallocate -g $rg -n $vmName | ConvertFrom-Json
    } catch {
        Throw "Unable to deallocate the VM"
    }
}

Function Start-VM {
    param (
        $rg,
        $vmName
    )
    try {
        az vm start -g $rg -n $vmName | ConvertFrom-Json
    } catch {
        Throw "Unable to start VM"
    }
}

Function Get-AzureVMPrice {
    [CmdletBinding()]

    Param
    (
        [Parameter(ValueFromPipeline,HelpMessage='The VM Sku to get prices for',Mandatory=$true)]
        [string]$vmSku,
        [Parameter(HelpMessage='The currency to report back',Mandatory=$true)]
        [string]$currencyCode,
        [Parameter(HelpMessage='Azure region to get prices for',Mandatory=$true)]
        [string]$region
    )

    #Setup parameters
    $Parameters = @{
        currencyCode = $currencyCode
        '$filter' = "serviceName eq 'Virtual Machines' and armSkuName eq `'$vmSku`' and armRegionName eq `'$region`' and type eq 'Consumption'"
    }

    #Make a web request for the prices
    try {
        $request = Invoke-WebRequest -UseBasicParsing -Uri "https://prices.azure.com/api/retail/prices" -Body $Parameters -Method Get
        $result = $request.Content | ConvertFrom-JSON | Select-Object -ExpandProperty Items | Sort-Object effectiveStartDate -Descending | Select-Object -First 1

        $vmPrice = [PSCustomObject]@{
                    SKUName = $($result.armSkuName) 
                    Region = $($result.armRegionName) 
                    Currency = $($result.currencyCode)
                    Product_Name = $($result.productName)
                    Price_Per_Minute = if ($($result.unitOfMeasure) -match 'Hour') {$($result.retailPrice)/60 } else { 0 }
                    Price_Per_Hour = if ($($result.unitOfMeasure) -match 'Hour') { $($result.retailPrice) } else { 0 }
                    Price_Per_Day = if ($($result.unitOfMeasure) -match 'Hour') { $($result.retailPrice) * 24 } else { 0 }
                }
        
        if ([string]::IsNullOrEmpty($vmPrice.SKUName)) {
            Throw
        } else {
            Return $vmPrice
        }

    } catch {
        Write-Error "Error processing request, check the SKU and region are valid"
        Write-Error $_
    }
}

Function Get-AzureVMSKUs {
    [CmdletBinding()]

    Param
    (
        [Parameter(HelpMessage='Azure region to get prices for',Mandatory=$true)]
        [string]$region
    )

    #Setup parameters
    $Parameters = @{
        currencyCode = $currencyCode
        '$filter' = "serviceName eq 'Virtual Machines' and  armRegionName eq `'$region`' and type eq 'Consumption'"
    }

    #Make a web request for the prices
    try {
        $request = Invoke-WebRequest -UseBasicParsing -Uri "https://prices.azure.com/api/retail/prices" -Body $Parameters -Method Get
        $result = $request.Content | ConvertFrom-JSON | Select-Object -ExpandProperty Items | Select-Object armSkuName

        $SKUs = foreach ($item in $result) {
            $item.armSkuName
        }

        Return $SKUs | Select-Object -Unique | Sort-Object
    } catch {
        Write-Error "Error processing request, check the region and currency are valid"
        Write-Error $_
    }
}

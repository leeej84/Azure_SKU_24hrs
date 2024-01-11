<#
.AUTHOR
Go-EUC - Leee Jeffries - 04.10.23

.SYNOPSIS
Runs a terraform process to deploy a single VM in Azure, the VM is then added as a trusted host for WinRM so that remote execution of code can be handled.

.DESCRIPTION
This script is designed to configure a VM in Azure and make it ready for testing.

.PARAMETER externalIP
External IP of the machine to be added to the Azure NSG to allow full access to the VM

.PARAMETER rootFolder
The root folder where all output files will be stored

.PARAMETER testTitle
The name of the folder to be created for the test plan to store all results

.PARAMETER testIterations
The number of iterations to perform for the test default is 1

.EXAMPLE
& '.\Configure.ps1' -ExternalIP '10.60.93.10'

Deploys the Azure VM, Allows access to the Azure VM from the IP specified, Adds the VM's external IP to Trusted Hosts for WinRM
#>

[CmdletBinding()]

Param
(
    [Parameter(HelpMessage='External IP to allow access to the Azure VM')]
    [string]$externalIP,
    [Parameter(HelpMessage='The root folder where all output files will be stored',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$rootFolder,
    [Parameter(HelpMessage='The name of the folder to be created for the test plan to store all results',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$testTitle,
    [Parameter(HelpMessage='The number of iterations to perform for the test, default is 1',Mandatory=$true)]
    [int]$testIterations=1
)

#Dot source the functions written
. .\Functions.ps1

try {
    #If external IP is not specified, work it out and try and use that
    $autoExternalIP = Get-ExternalIP
    if (!($externalIP) -and !($autoExternalIP))  {
        Throw "No external IP address was specified and it could not be automatically detected."
    } elseif (!($externalIP)) {
        $ExternalIP = $autoExternalIP
    }

    #Check Azure CLI is installed
    if (Get-Product -product 'Azure CLI') {
        #Azure CLI found - continuing
    } else {
        Throw "Azure CLI is not installed and the script cannot continue, please install Azure CLI"
    }

    #Check if terraform is in the path environment variable
    if (Invoke-Expression "terraform") {
        #Terraform is installed and in the path
    } else {
        Throw "Terraform is not installed or is not in the path so that it can be run without specifying a location. Please ensure terraform is installed and added to the PATH variable"
    }

    #Check for az login
    $azCliLoginCheck = Invoke-Expression "az account show -o jsonc"
    if ($azCliLoginCheck) {
        #az cli returned a response so we are already logged in
        #json object should be received
    } else {
        #Not currently logged in with az cli, prompting for login
        Invoke-Expression "az login"
    }

    #Start the terraform deployment
    #Initiate terraform
    Write-Host "Deploying resources with terraform"
    Start-Process terraform.exe -ArgumentList "init" -Wait
    #Run a terraform plan to asses the current environment
    Start-Process terraform.exe -ArgumentList "plan" -Wait
    #Implement the terraform application and wait for it to finish
    $process = Start-Process terraform.exe -ArgumentList "apply", "-auto-approve", "-var=`"ext_ip=$externalIP`"" -PassThru
    $process | Wait-Process
    #Output the results of the build process to a json file for later integrations
    $output = Invoke-Expression "terraform.exe output -json"
    $output | Out-File .\values.json -Force

    #Check for the TF outputs
    Write-Host "Reading values from terraform"
    if (Test-Path ".\values.json") {
        #Values file found, we will now pull in the details
        $tfOutputs = Get-Content ".\values.json" | ConvertFrom-Json
    } else {
        Write-Host $_
        Throw "Terraform did not output the values from deployment, the process of deployment cannot continue. Make sure you clean up your azure resources manually."
    }

    #Add the external IP of the VM created the the trusted hosts for WinRM
    if (-not [string]::IsNullOrEmpty($tfOutputs.public_ip_address.value)) {
        # Make sure the WinRM service is started on the client running this script or this command will fail and unencrypted traffic is allowed
        if ($(Get-Service WinRM).Status -ne "Running") { 
            Start-Service WinRM 
        }
        Set-Item WSMan:\localhost\Client\AllowUnencrypted -Value true
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value $tfOutputs.public_ip_address.value -Confirm:$false -Force
    } else {
        Throw "Unable to add the provisioned VM to WinRM Trusted Hosts, check the WinRM service is running on this machine and you have the relevant admin permissions."
    }

    foreach ($iteration in 1..$testIterations) {
        #Test runs to perform
        Write-Host "Running run number $iteration for vm $testTitle out of $testIterations runs"
        
        #Make sure the VM is started
        do {       
            Start-VM -rg $tfOutputs.resource_group_name.value -vmName $tfOutputs.vm_name.value     
            Start-Sleep -Seconds 30
            $powerState = Get-VMPowerState -rg $tfOutputs.resource_group_name.value -vmName $tfOutputs.vm_name.value
            Write-Host "Checking VM power state to make sure its running"
            Start-Sleep -Seconds 30
        } until ($powerState -eq "VM running")
        
        #Test remote connection with the Azure VM
        try {
            Test-WSMan -ComputerName $tfOutputs.public_ip_address.value | Out-Null
        } catch {
            Throw "Unable to test the winRM remoting with the remote machine, connection failed"
        } 

        #Create a PS Remoting Session
        try {
            $session = Create-PSSession -username $($tfOutputs.admin_username.value) -password $($tfOutputs.admin_password.value) -ipaddress $($tfOutputs.public_ip_address.value)
        } catch {
            Write-Error "There was an error connecting to the remote machine, cannot proceed."
        }
        
        #Set the testTitle
        $folderName = "run_$($iteration)"
        Write-Host "Folder location set to $rootFolder\$($testTitle)_$folderName"

        #Create local folder structure for storing test results
        try {
            New-Item -Path "$rootFolder\$($testTitle)_$folderName" -ItemType Directory -Force | Out-Null
        } catch {
            Throw "Unable to create local folder structure for storing test results"
        }

        #Create remote folder structure for storing test results
        try {
            Invoke-Command -Session $session -ScriptBlock {
               param (
                $rootFolder,
                $testTitle,
                $folderName 
               )
               New-Item -Path "$rootFolder\$($testTitle)_$folderName" -ItemType Directory -Force | Out-Null 
            } -ArgumentList $rootFolder, $testTitle, $folderName
        } catch {
            Throw "Unable to remote folder structure for storing test results"
        }

        #Copy script files up
        Invoke-Command -Session $session -ScriptBlock { If (!(Test-Path "C:\Scripts")) {New-Item C:\Scripts -ItemType Directory | Out-Null}}
        Copy-Item -Path .\TestRun.ps1 -Destination "C:\Scripts\" -ToSession $session -Force
        Copy-Item -Path .\test_config.json -Destination "C:\Scripts\" -ToSession $session -Force
        
        #Run scripted tasks
        Write-Host "Running Test - $testTitle - Run $iteration"
        Invoke-Command -Session $session -Scriptblock {
            param (
                $rootFolder,
                $testTitle,
                $folderName
            )
            
            $process = Start-Process PowerShell.exe -ArgumentList "-ExecutionPolicy Bypass", "-File C:\Scripts\TestRun.ps1", "-rootFolder $rootFolder","-testTitle $testTitle","-folderName $folderName"  -PassThru
            $process | Wait-Process
        } -ArgumentList $rootFolder,$testTitle,$folderName

        #Gather all files
        Write-Host "Copying Test Results"
        Copy-Item -FromSession $session -Path "$rootFolder\$($testTitle)_$folderName\*" -Destination "$rootFolder\$($testTitle)_$folderName" -Recurse -Force

        #Deallocate and reallocate the VM
        Deallocate-VM -rg $tfOutputs.resource_group_name.value -vmName $tfOutputs.vm_name.value
        
        do {       
            Start-VM -rg $tfOutputs.resource_group_name.value -vmName $tfOutputs.vm_name.value     
            Start-Sleep -Seconds 30
            $powerState = Get-VMPowerState -rg $tfOutputs.resource_group_name.value -vmName $tfOutputs.vm_name.value
            Write-Host "Checking VM power state to make sure its running"
            Start-Sleep -Seconds 30
        } until ($powerState -eq "VM running")
    }
} catch {
    Write-Error $_
}


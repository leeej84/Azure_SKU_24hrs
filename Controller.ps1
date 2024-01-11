[CmdletBinding()]

Param
(
    [Parameter(HelpMessage='The root folder where all output files will be stored',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$rootFolder,
    [Parameter(HelpMessage='The number of iterations to perform for the test, default is 1',Mandatory=$true)]
    [int]$testIterations=1,
    [Parameter(HelpMessage='VM SKUs to test',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMSKUs,
    [Parameter(HelpMessage='The current SKU listed in variables.tf',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$previousVMSKU

)

foreach ($sku in $VMSKUs) {
    Write-Host "Running tests for VM $sku"
    #Get the content of the variables.tf file
    $tfTemp = Get-Content .\variables.tf

    #Replace the VM SKU within variables.tf
    $tfTemp.Replace($previousVMSKU,$sku) | Set-Content .\variables.tf
    
    #Run the configure script with the specified SKU
    .\Configure.ps1 -rootFolder $rootFolder -testTitle $sku -testIterations $testIterations

    #Last step so we can change the SKU on the next step
    $previousVMSKU = $Sku
}

#Destroy the infra using terraform as we're done testing
#Implement the terraform application and wait for it to finish
$process = Start-Process terraform.exe -ArgumentList "destroy", "-auto-approve" -PassThru
$process | Wait-Process

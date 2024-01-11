$rootFolder = "C:\Temp\SKU_Testing"

$folders = gci -Path $rootFolder | Where {$_.PSIsContainer -eq $true}

$summary = foreach ($folder in $folders) {
    $azureInfo = ""
    $sysInfo = ""
    if (Test-Path "$($folder.FullName)\Azure_Info.json") {$azureInfo = Get-Content -Path "$($folder.FullName)\Azure_Info.json" | ConvertFrom-Json}
    if (Test-Path "$($folder.FullName)\Sys_Info.json") {$sysInfo = Get-Content -Path "$($folder.FullName)\Sys_Info.json" | ConvertFrom-Json}

    if (($null -ne $azureInfo) -and ($null -ne $sysInfo)) {
        [PSCustomObject] @{
            Test = $($folder.FullName).split("\")[$($folder.FullName).split("\").count-1]
            SKU = $azureInfo.compute.vmSize
            Processor = "$($sysInfo.cSProcessors.Name) - $($sysInfo.cSProcessors.Description) - $($sysInfo.cSProcessors.Architecture)"
            Processor_Speed = $sysInfo.CsProcessors.CurrentClockSpeed
            Processor_Cores = "$($sysinfo.CsProcessors.NumberOfCores) / $($sysinfo.CsProcessors.NumberOfLogicalProcessors)"
            Errors = if (Test-Path "$($folder.FullName)\$($folder.Name)_ERRORS.log") { "Yes" } else { "No" }
        }
    }
}

$summary
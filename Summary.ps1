$rootFolder = "C:\Temp\SKU_Testing"
$folders = Get-ChildItem -Path $rootFolder | Where {$_.PSISContainer -eq $true}

$allResults.Clear()

$resultTask = "Perf","Timings"

foreach ($folder in $folders) {
    foreach ($task in $resultTask) {
        $subFolders = Get-ChildItem -Path $folder.FullName | Where {$_.PSISContainer -eq $true}
        foreach ($subFolder in $subFolders) {
            Write-Host "Working on $($folder.Name) > $($subFolder.Name)"
            $sysinfo = Get-Content "$($subFolder.FullName)\Sys_Info.json" | ConvertFrom-Json
            #Write-Host "Importing "$($subFolder.FullName)\Performance.csv"
            $performanceMetrics = Import-Csv -Path "$($subFolder.FullName)\Performance.csv"
            #Write-Host "Importing "$($subFolder.FullName)\timings.csv"
            $timings = Import-Csv -Path "$($subFolder.FullName)\timings.csv"
            #Write-Host "$($sysinfo.CsProcessors.Name)"

            $performanceResults = $performanceResults + $performanceMetrics
            $timingsResults = $timingsResults + $timings
        }

        if ($task -eq "Perf") {
            #Loop through performance metrics
            Write-Host "Working on Performance metrics for $folder"
            $perfItems = $($performanceResults.syncroot | Select -First 1 | Get-Member).Name | Where-Object {$_ -match "\\"}
            $perfAverage = foreach ($item in $perfItems) {
                [PSCustomObject] @{
                    Test = $folder
                    Metric = $item
                    CPU = "$($sysinfo.csProcessors.Name)_$($sysinfo.CsProcessors.Description)_$($sysinfo.CsProcessors.Architecture)"
                    Average = $($($performanceResults | Where-Object {$_.$($item).Length -gt 1} | Select-Object -ExpandProperty $($item)) | Sort-Object | Measure-Object -Average).Average
                    Maximum = $($($performanceResults | Where-Object {$_.$($item).Length -gt 1} | Select-Object -ExpandProperty $($item)) | Sort-Object | Measure-Object -Maximum).Maximum
                    Minimum = $($($performanceResults | Where-Object {$_.$($item).Length -gt 1} | Select-Object -ExpandProperty $($item)) | Sort-Object | Measure-Object -Minimum).Minimum
                }           
            }
        $perfAverage
        }
        
        if ($task -eq "Timings") {
            #Loop through timings
            Write-Host "Working on task timings for $folder"
            $excludedItems = "Equals","GetHashCode","GetType","ToString"
            $timingsItems = $($timingsResults.syncroot | Select -First 1 | Get-Member).Name | Where-Object {$_ -notin $excludedItems}
            $timingsAverage = foreach ($item in $timingsItems) {
                [PSCustomObject] @{
                    Test = $folder
                    Task = $item
                    CPU = "$($sysinfo.csProcessors.Name)_$($sysinfo.CsProcessors.Description)_$($sysinfo.CsProcessors.Architecture)"
                    Average = $($($timingsResults | Where-Object {$_.$($item).Length -gt 1} | Select-Object -ExpandProperty $($item)) | Sort-Object | Measure-Object -Average).Average
                    Maximum = $($($timingsResults | Where-Object {$_.$($item).Length -gt 1} | Select-Object -ExpandProperty $($item)) | Sort-Object | Measure-Object -Maximum).Maximum
                    Minimum = $($($timingsResults | Where-Object {$_.$($item).Length -gt 1} | Select-Object -ExpandProperty $($item)) | Sort-Object | Measure-Object -Minimum).Minimum
                }
            }
        $timingsAverage
        }
        
        Write-Host "Deciding which files to export $task"
        if ($task -eq "Perf") {
            Write-Host "Exporting Performance summery for $folder to $($folder.FullName)"
            $perfAverage | Export-Csv -Path "$($folder.fullName)\Summary_Perf.csv" -NoTypeInformation
        } else {
            Write-Host "Exporting timings summery for $folder to $($folder.FullName)"
            $timingsAverage | Export-Csv -Path "$($folder.fullName)\Summary_Timings.csv" -NoTypeInformation
        }
    }
}
    
    
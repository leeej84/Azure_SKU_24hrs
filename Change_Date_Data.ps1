$rootFolder = "C:\Temp\LogFiles"
$task = "perfmon"
$folders = Get-ChildItem $rootFolder | Where {$_.PSIsContainer -eq $true}

if ($task -eq "timings") {
    foreach ($folder in $folders) {
        $file = Get-ChildItem -Path $folder.FullName -Filter "*timings.csv"
        $data = Import-Csv -Path $file.FullName
        Remove-Item $file.FullName -Force
        $i = 1
        foreach ($row in $data) {
            $row.DateTime = $(Get-Date).AddMinutes($i).ToString("dd/MM/yyyy hh:mm:ss")
            $row | Export-Csv -Path $file.FullName -Append -NoTypeInformation
            #$row | Export-Csv -Path "$rootFolder\temp.csv" -Append
            $i++
        }
    }
}

if ($task -eq "perfmon") {
    foreach ($folder in $folders) {
        $file = Get-ChildItem -Path $folder.FullName -Filter "*perfmon.csv"
        $data = Import-Csv -Path $file.FullName
        Remove-Item $file.FullName -Force
        $i = 1
        foreach ($row in $data) {
            $row.'(PDH-CSV 4.0) (Coordinated Universal Time)(0)' = $(Get-Date).AddSeconds($i).ToString("dd/MM/yyyy hh:mm:ss")
            $row | Export-Csv -Path $file.FullName -Append -NoTypeInformation
            #$row | Export-Csv -Path "$rootFolder\temp.csv" -Append -NoTypeInformation
            $i++
        }
    }
}
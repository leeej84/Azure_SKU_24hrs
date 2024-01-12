[CmdletBinding()]

Param
(
    [Parameter(HelpMessage='The root folder where all output files will be stored',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$rootFolder,
    [Parameter(HelpMessage='The root folder where all output files will be stored',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$testTitle,
    [Parameter(HelpMessage='The name of the folder to be created for the test plan to store all results',Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$folderName
)

Start-Transcript -Path "C:\Windows\Temp\Test_Run_Transscript.log"

Function Create-File {
    [CmdLetBinding()]
    Param (
        [Parameter(Mandatory=$true,HelpMessage="specify the file size in bytes")]
        [int]$fileSize,
        [Parameter(Mandatory=$true,HelpMessage="specify the location to create the file")]
        [string]$location
    )
    #Run FSUtil
    if (!(Test-Path $location)) { New-Item -Path $location -ItemType Directory }
    if (Test-Path $("$location\$fileSize.file")) { Remove-Item -Path $("$location\$fileSize.file") -Force }
    $process = Start-Process fsutil -ArgumentList "file createnew $("$location\$fileSize.file") $fileSize" -PassThru
    $process | Wait-Process

    return $("$location\$fileSize.file")
}

Function Copy-Files {
    [CmdLetBinding()]
    Param (
        [Parameter(Mandatory=$true,HelpMessage="Template file to copy")]
        [string]$templateFile,
        [Parameter(Mandatory=$true,HelpMessage="Number of items to duplicate")]
        [int]$itemCopies,
        [Parameter(Mandatory=$true,HelpMessage="Working folder")]
        [string]$workingFolder
    )

    try {
        if (!(Test-Path -Path $templateFile)) {
            Throw "Error locating the template file to copy, please try again"
        } else {
            return $(Measure-Command {
                foreach ($item in 1..$itemCopies) {
                    Copy-Item -Path $templateFile -Destination "$workingFolder\$item.file" -Force
                }
            }).TotalMilliseconds
        }
    } catch {
        Write-Error $_
    }
    
}

Function Read-Files {
    [CmdLetBinding()]
    Param (
        [Parameter(Mandatory=$true,HelpMessage="Working folder")]
        [string]$workingFolder
    )

    try {
        if (!(Test-Path -Path $workingFolder)) {
            Throw "Error opening the workling folder, please try again"
        } else {
            return $(Measure-Command {
                $files = Get-ChildItem -Path $workingFolder 
                foreach ($item in $files) {
                    Get-Content -Path $item.fullname | Out-Null
                }
            }).TotalMilliseconds
        }
    } catch {
        Write-Error $_
    }
    
}

Function Remove-Folder {
    [CmdLetBinding()]
    Param (
        [Parameter(Mandatory=$true,HelpMessage="Working folder")]
        [string]$workingFolder
    )

    try {
        if (!(Test-Path -Path $workingFolder)) {
            Throw "Error locating the working folder, please try again"
        } else {
            return $(Measure-Command { Remove-Item -Path $workingFolder -Recurse -Force -Confirm:$false}).TotalMilliseconds
        }
    } catch {
        Write-Error $_
    }
    
}

#7Zip Wrapper Function
Function Run-Compression {
    [CmdLetBinding()]
    Param (
        [Parameter(Mandatory=$true,HelpMessage="Action to perform, compress or decompress")]
        [ValidateSet("compress","decompress")]
        [string]$action,
        [Parameter(Mandatory=$true,HelpMessage="Location of archives to decompress or compress")]
        [string]$location,
        [Parameter(Mandatory=$false,HelpMessage="Level of compression to use 5=normal, 7=maximum, 9=ultra")]
        [ValidateSet(5,7,9)]
        [int]$compressionLevel=5
    )

    Switch($action) {
            "compress" {
                return $(Measure-Command { 
                    $process = Start-Process -FilePath "C:\Program Files\7-Zip\7z.exe" -ArgumentList "a","$location\archive.7z","$location","-mx$compressionLevel" -PassThru
                    $process | Wait-Process
                }).TotalMilliseconds
            }
            "decompress" {
                return $(Measure-Command {
                    $process = Start-Process -FilePath "C:\Program Files\7-Zip\7z.exe" -ArgumentList "x","$location\*.7z","-oC:\Windows\Temp","-y" -PassThru
                    $process | Wait-Process
                }).TotalMilliseconds
            }
        }
}
try {
    ##Download and install 7Zip
    if (!(Test-Path "C:\Program Files\7-Zip\7z.exe")) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "https://www.7-zip.org/a/7z2301-x64.exe" -Method Get -OutFile "C:\Temp\7z.exe"
            $Process = Start-Process "C:\Temp\7z.exe" -ArgumentList "/S" -PassThru
        } catch {
            Write-Error "Could not download or install 7Zip"
        }
    }

    #Get the current date and time then add 24 hrs
    $currentDateTime = Get-Date
    $finishDateTime = $currentDateTime.AddHours(24)

    #Start performance capture
    Write-Host "Starting performance capture"
    Start-Job -Name "Performance_Capture" -ScriptBlock {
        param (
            $rootFolder,
            $testTitle,
            $folderName
        )
        $counters = "\Processor(_Total)\% Processor Time","\Memory\% Committed Bytes in Use","\Memory\Available MBytes","\LogicalDisk(C:)\Current Disk Queue Length","\LogicalDisk(C:)\Disk Reads/sec","\LogicalDisk(C:)\Disk Writes/sec","\Network Interface(*)\Bytes Received/sec","\Network Interface(*)\Bytes Sent/sec","\Network Interface(*)\Bytes Total/sec"
        Get-Counter -Continuous -SampleInterval 1 -Counter $counters | Export-Counter -Path "$rootFolder\$($testTitle)_$($folderName)\$($testTitle)_$($folderName)_perfmon.csv" -FileFormat CSV -Force
    } -ArgumentList $rootFolder,$testTitle,$folderName

    #Run the test in a loop for 24 hours
    do {
        #Read Config File
        $config = Get-Content "C:\Scripts\test_config.json" | ConvertFrom-Json

        #Get Azure Info
        $azureDetails = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | ConvertTo-Json -Depth 64
        $azureDetails | Out-File "$rootFolder\$($testTitle)_$folderName\Azure_Info.json"

        #Export the system info
        Get-ComputerInfo | ConvertTo-Json | Out-File "$rootFolder\$($testTitle)_$folderName\Sys_Info.json"

        #Loop through each test
        $results = foreach ($test in $($config.tests.psobject.Properties.name)) {
            #Create folder structures
            New-Item -Path $config.GlobalSettings.tempFolder -ItemType Directory -Force | Out-Null
            New-Item -Path $config.GlobalSettings.workingFolder -ItemType Directory -Force | Out-Null
            
            $templateFile = Create-File -fileSize $config.Tests.$test.fileSize -location $config.GlobalSettings.tempFolder
            $copyResult = Copy-Files -templateFile $templateFile -itemCopies $config.Tests.$test.numberOfFiles -workingFolder $config.GlobalSettings.workingFolder
            Write-Host "Copying $($config.Tests.$test.numberOfFiles) at $($config.Tests.$test.fileSize) size, took $copyResult (ms)"
            $ReadResult = Read-Files -workingFolder $config.GlobalSettings.workingFolder
            Write-Host "Reading $($config.Tests.$test.numberOfFiles) at $($config.Tests.$test.fileSize) size, took $ReadResult (ms)"
            $compressionResults = foreach ($compressionlevel in $(5,7,9)) {
                $compressResult = Run-Compression -action compress -location $config.GlobalSettings.workingFolder -compressionLevel 5
                Write-Host "Compressing $($config.Tests.$test.numberOfFiles) files at $($config.Tests.$test.fileSize) size, took $compressResult (ms) with $compressionlevel compression level"
                $decompressResult = Run-Compression -action decompress -location $config.GlobalSettings.workingFolder
                Write-Host "Decompressing $($config.Tests.$test.numberOfFiles) files at $($config.Tests.$test.fileSize) size, took $decompressResult (ms) with $compressionlevel compression level"
                [PSCustomObject]@{
                    compressLevel = $compressionlevel
                    compressResult = $compressResult
                    decompressResult = $decompressResult
                }
            }
            $cleanupResult = Remove-Folder -workingFolder $config.GlobalSettings.workingFolder
            $cleanupResult = $cleanupResult + $(Remove-Folder -workingFolder $config.GlobalSettings.tempFolder)   
            
            Write-Host "Cleaning up all files after the test took $cleanupResult (ms)"

            [PSCustomObject]@{
                DateTime = $(Get-Date).ToString("dd/MM/yyyy hh:mm:ss")
                File_Size = $config.Tests.$test.fileSize
                Num_Files = $config.Tests.$test.numberOfFiles
                Copy = $copyResult
                Read = $ReadResult
                Compression_Normal = $compressionResults | Where-Object {$_.compressLevel -eq 5} | Select-Object -ExpandProperty compressResult
                Decompression_Normal = $compressionResults | Where-Object {$_.compressLevel -eq 5} | Select-Object -ExpandProperty decompressResult
                Compression_Maximum = $compressionResults | Where-Object {$_.compressLevel -eq 7} | Select-Object -ExpandProperty compressResult
                Decompression_Maximum = $compressionResults | Where-Object {$_.compressLevel -eq 7} | Select-Object -ExpandProperty decompressResult
                Compression_Ultra = $compressionResults | Where-Object {$_.compressLevel -eq 9} | Select-Object -ExpandProperty compressResult
                Decompression_Ultra = $compressionResults | Where-Object {$_.compressLevel -eq 9} | Select-Object -ExpandProperty decompressResult
                Cleanup = $cleanupResult
            }
        }

        #Write out Results
        if (!(Test-Path "$rootFolder\$($testTitle)_$($folderName)")) { New-Item -Path "$rootFolder\$($testTitle)_$($folderName)" -ItemType Directory | Out-Null}
        $results | Export-CSV -Path "$rootFolder\$($testTitle)_$($folderName)\$($testTitle)_$($folderName)_timings.csv" -NoTypeInformation -Append

    } until ($(Get-Date) -gt $finishDateTime) 

    #Stop performance capture
    Get-Job -Name Performance_Capture  | Stop-Job | Receive-Job | Remove-Job

    Stop-Transcript
} catch {
    $_ | Out-File "$rootFolder\$($testTitle)_$($folderName)\$($testTitle)_$($folderName)_ERRORS.log"
}
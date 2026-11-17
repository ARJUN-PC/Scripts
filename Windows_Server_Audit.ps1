
#requires -version 5.1
<#
Windows Server Read-Only Audit
- Console output only.
- Does not modify server configuration, services, registry, files, or scheduled tasks.
- Run in an elevated PowerShell session for complete results.
#>

$ErrorActionPreference = 'Continue'
$DaysToCheck = 30
$Since = (Get-Date).AddDays(-$DaysToCheck)

function Write-Section {
    param([string]$Title)
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Write-Value {
    param([string]$Label, $Value)
    if ($null -eq $Value -or "$Value" -eq '') {
        $Value = 'Not available'
    }
    Write-Host ("{0,-34}: {1}" -f $Label, $Value)
}

Write-Host "`nWINDOWS SERVER AUDIT - READ ONLY" -ForegroundColor Green
Write-Host ("Audit time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
Write-Host "No server configuration changes will be made."

# 1. Hostname / Date / Time / Timezone
Write-Section "HOSTNAME / DATE / TIME / TIMEZONE"

Write-Value "Hostname" $env:COMPUTERNAME
Write-Value "Date and time" (Get-Date -Format 'ddd MM/dd/yyyy HH:mm:ss.ff')
Write-Value "Timezone" (Get-TimeZone).Id

# 2. Operating System Information
Write-Section "OPERATING SYSTEM INFORMATION"

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem

Write-Value "OS name" $os.Caption
Write-Value "OS version" $os.Version
Write-Value "OS build" $os.BuildNumber
Write-Value "OS architecture" $os.OSArchitecture
Write-Value "System type" $cs.SystemType
Write-Value "Manufacturer" $cs.Manufacturer
Write-Value "Model" $cs.Model

$installDate = if ($os.InstallDate) {
    $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss')
} else {
    'Not available'
}

$lastBootTime = if ($os.LastBootUpTime) {
    $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
} else {
    'Not available'
}

Write-Value "Original install date" $installDate
Write-Value "Last boot time" $lastBootTime

if ($os.LastBootUpTime) {
    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Value "System uptime" ("{0} days, {1} hours, {2} minutes" -f [math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes)
}

# 3. System Details
Write-Section "SYSTEM DETAILS"

$cpu = @(Get-CimInstance Win32_Processor | Sort-Object Name -Unique)

foreach ($item in $cpu) {
    Write-Value "Processor" $item.Name
    Write-Value "Cores" $item.NumberOfCores
    Write-Value "Logical processors" $item.NumberOfLogicalProcessors
    Write-Value "Maximum clock speed (MHz)" $item.MaxClockSpeed
}

Write-Value "Total physical memory (GB)" ([math]::Round($cs.TotalPhysicalMemory / 1GB, 2))
Write-Value "Free physical memory (GB)" ([math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 2))

# 4. Current Resource Utilization
Write-Section "CURRENT RESOURCE UTILIZATION"

$cpuLoad = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
Write-Value "Average CPU load (%)" ([math]::Round($cpuLoad.Average, 2))

$memoryUsed = $cs.TotalPhysicalMemory - ($os.FreePhysicalMemory * 1KB)
$memoryPercent = if ($cs.TotalPhysicalMemory -gt 0) {
    100 * $memoryUsed / $cs.TotalPhysicalMemory
} else {
    0
}

Write-Value "Memory usage (%)" ([math]::Round($memoryPercent, 2))

Write-Host "`nTop 10 processes by CPU time:"

Get-Process -ErrorAction SilentlyContinue |
    Sort-Object CPU -Descending |
    Select-Object -First 10 ProcessName, Id,
        @{N='CPUSeconds';E={if ($null -ne $_.CPU) {[math]::Round($_.CPU,2)} else {0}}},
        @{N='WorkingSetMB';E={[math]::Round($_.WorkingSet64 / 1MB,2)}} |
    Format-Table -AutoSize

Write-Host "`nTop 10 processes by memory:"

Get-Process -ErrorAction SilentlyContinue |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 10 ProcessName, Id,
        @{N='WorkingSetMB';E={[math]::Round($_.WorkingSet64 / 1MB,2)}},
        @{N='CPUSeconds';E={if ($null -ne $_.CPU) {[math]::Round($_.CPU,2)} else {0}}} |
    Format-Table -AutoSize

# 5. Plesk Version
Write-Section "PLESK VERSION"

$pleskPaths = @(
    "${env:ProgramFiles(x86)}\Plesk\bin\plesk.exe",
    "$env:ProgramFiles\Plesk\bin\plesk.exe"
)

$pleskExe = $pleskPaths |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if ($pleskExe) {
    Write-Host "Plesk executable found: $pleskExe"
    & $pleskExe version 2>&1
} else {
    Write-Host "Plesk is not installed or the Plesk CLI was not found."
}

# 6. Windows Updates
Write-Section "WINDOWS UPDATES"

try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $updateResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")

    Write-Value "Pending update count" $updateResult.Updates.Count

    if ($updateResult.Updates.Count -gt 0) {
        $updateResult.Updates |
            ForEach-Object {
                [pscustomobject]@{
                    Title = $_.Title
                    IsDownloaded = $_.IsDownloaded
                    IsMandatory = $_.IsMandatory
                }
            } | Format-Table -AutoSize
    } else {
        Write-Host "No applicable pending updates were returned by Windows Update."
    }
} catch {
    Write-Host "Unable to query Windows Update: $($_.Exception.Message)"
}

# 7. Disk Usage
Write-Section "DISK USAGE"

$logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

$diskRows = foreach ($disk in $logicalDisks) {
    [pscustomobject]@{
        Drive = $disk.DeviceID
        VolumeName = $disk.VolumeName
        SizeGB = [math]::Round($disk.Size / 1GB, 2)
        FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        UsedPercent = if ($disk.Size -gt 0) {
            [math]::Round((1 - ($disk.FreeSpace / $disk.Size)) * 100, 2)
        } else {
            0
        }
    }
}

$diskRows | Format-Table -AutoSize

# 8. Windows License Activation
Write-Section "WINDOWS LICENSE ACTIVATION"

try {
    $licenses = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND LicenseStatus = 1" |
        Where-Object {
            $_.Name -like 'Windows*' -or $_.Description -like '*Windows*'
        }

    if ($licenses) {
        $licenses |
            Select-Object -First 5 Name, Description, LicenseStatus |
            Format-Table -AutoSize

        Write-Host "Windows activation: Licensed / Activated"
    } else {
        Write-Host "No activated Windows license entry was detected. Verify with slmgr.vbs /xpr."
    }
} catch {
    Write-Host "Unable to query Windows licensing: $($_.Exception.Message)"
}

# 9. Physical Disk / Storage Health
Write-Section "PHYSICAL DISK / STORAGE HEALTH"

Write-Host "`nWin32_DiskDrive:"

Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue |
    Select-Object Model, InterfaceType, Status,
        @{N='SizeGB';E={[math]::Round($_.Size / 1GB, 2)}} |
    Format-Table -AutoSize

if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
    Write-Host "`nGet-PhysicalDisk:"

    Get-PhysicalDisk -ErrorAction SilentlyContinue |
        Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus,
            @{N='SizeGB';E={[math]::Round($_.Size / 1GB, 2)}} |
        Format-Table -AutoSize
} else {
    Write-Host "Get-PhysicalDisk is not available on this system."
}

Write-Host "Note: Windows disk status does not guarantee RAID virtual-drive/array health."
Write-Host "For hardware RAID, verify using the controller vendor utility."

# 10. Antivirus / ESET Status
Write-Section "ANTIVIRUS / ESET STATUS"

$avProducts = Get-CimInstance -Namespace root/SecurityCenter2 `
    -ClassName AntiVirusProduct -ErrorAction SilentlyContinue

if ($avProducts) {
    $avProducts |
        Select-Object displayName, productState, pathToSignedProductExe |
        Format-Table -AutoSize
} else {
    Write-Host "SecurityCenter2 antivirus inventory is unavailable. Checking services/processes."
}

$esetServices = Get-Service -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match 'ESET|ekrn|ERA|EHttpSrv' -or
        $_.DisplayName -match 'ESET'
    }

if ($esetServices) {
    $esetServices |
        Select-Object Name, DisplayName, Status, StartType |
        Format-Table -AutoSize
} else {
    Write-Host "No ESET-related Windows service was detected."
}

$esetProcesses = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match 'ekrn|egui|ESET' } |
    Select-Object ProcessName, Id

if ($esetProcesses) {
    $esetProcesses | Format-Table -AutoSize
}

Write-Host "Note: Service/process presence alone does not confirm protection or signature health."

# 11. Database Services
Write-Section "DATABASE SERVICES"

$dbServices = Get-CimInstance Win32_Service |
    Where-Object {
        $_.Name -match 'mysql|maria|mssql|sqlserver|postgres' -or
        $_.DisplayName -match 'mysql|maria|sql server|postgres'
    } |
    Select-Object Name, DisplayName, State, StartMode

if ($dbServices) {
    $dbServices | Format-Table -AutoSize
} else {
    Write-Host "No matching database services detected."
}

# 12. Backup Software / Configuration Indicators
Write-Section "BACKUP SOFTWARE / CONFIGURATION INDICATORS"

$backupServices = Get-CimInstance Win32_Service |
    Where-Object {
        $_.Name -match 'Acronis|Veeam|Backup|Plesk' -or
        $_.DisplayName -match 'Acronis|Veeam|Backup'
    } |
    Select-Object Name, DisplayName, State, StartMode

if ($backupServices) {
    $backupServices | Format-Table -AutoSize
} else {
    Write-Host "No matching backup-related service was detected."
}

$backupApps = Get-ItemProperty `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -match 'Acronis|Veeam|Backup'
    } |
    Select-Object -Unique DisplayName, DisplayVersion, Publisher

if ($backupApps) {
    Write-Host "`nInstalled backup-related applications:"
    $backupApps | Format-Table -AutoSize
}

Write-Host "`nScheduled task names containing backup-related terms:"

$backupTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object {
        $_.TaskName -match 'backup|acronis|veeam|plesk' -or
        $_.TaskPath -match 'backup|acronis|veeam|plesk'
    } |
    Select-Object TaskPath, TaskName, State

if ($backupTasks) {
    $backupTasks | Format-Table -AutoSize
} else {
    Write-Host "No matching scheduled tasks detected."
}

Write-Host "Note: These checks do not prove that backups are configured or restorable."
Write-Host "Verify actual backup status in the respective backup management interface."


# 13. Event Logs - Last 30 Days
Write-Section "EVENT LOG - LAST $DaysToCheck DAYS"

foreach ($logName in @('System', 'Application')) {

    Write-Host "`n$logName log - Critical / Error / Warning counts"
    Write-Host "Period: Last $DaysToCheck days"

    try {
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName = $logName
            StartTime = $Since
            Level = @(1, 2, 3)
        } -ErrorAction Stop)

        if ($events.Count -gt 0) {

            # Safely convert event records into readable objects
            $eventDetails = foreach ($event in $events) {

                $level = try {
                    $event.Level
                } catch {
                    $null
                }

                $levelName = switch ($level) {
                    1 { 'Critical' }
                    2 { 'Error' }
                    3 { 'Warning' }
                    default { 'Unknown' }
                }

                $eventMessage = try {
                    $event.FormatDescription()
                } catch {
                    try {
                        $event.Message
                    } catch {
                        'Event message unavailable'
                    }
                }

                if ([string]::IsNullOrWhiteSpace($eventMessage)) {
                    $eventMessage = 'Event message unavailable'
                }

                [PSCustomObject]@{
                    TimeCreated = $event.TimeCreated
                    Level = $levelName
                    EventID = $event.Id
                    Provider = $event.ProviderName
                    Message = ($eventMessage -replace '\s+', ' ')
                }
            }

            # Event severity summary
            $eventDetails |
                Group-Object Level |
                Select-Object @{N='Severity';E={$_.Name}}, Count |
                Format-Table -AutoSize

            # Latest 15 significant events
            Write-Host "`nLatest 15 significant events:"

            $eventDetails |
                Select-Object -First 15 TimeCreated, Level, EventID, Provider,
                    @{N='Message';E={
                        if ($_.Message.Length -gt 250) {
                            $_.Message.Substring(0,250)
                        } else {
                            $_.Message
                        }
                    }} |
                Format-List

        } else {
            Write-Host "No Critical, Error, or Warning events found."
        }

    } catch {
        Write-Host "Unable to read $logName log: $($_.Exception.Message)"
    }
}

# 14. Audit Completed
Write-Section "AUDIT COMPLETED"

Write-Host ("Completed at: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
Write-Host "Read-only audit finished."
Write-Host "No report file was created and no server settings were changed." -ForegroundColor Green

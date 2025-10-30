# ===============================================================================
#  GPU Virtualization & Partitioning Tool v3.0 MODERN
#  Unified Hyper-V Manager with GPU Partition Support
# ===============================================================================

# ===============================================================================
#  AUTOMATIC UAC ESCALATION
# ===============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host ""
    Write-Host "  [!] This script requires administrator privileges." -ForegroundColor Yellow
    Write-Host "  [*] Requesting UAC elevation..." -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds 1

    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ===============================================================================
#  UI CONFIGURATION
# ===============================================================================

$UIConfig = @{
    Primary = 'Cyan'
    Success = 'Green'
    Warning = 'Yellow'
    Error = 'Red'
    Info = 'Blue'
    Accent = 'Magenta'
    Neutral = 'Gray'
    DarkNeutral = 'DarkGray'
}

# ===============================================================================
#  CORE FUNCTIONS
# ===============================================================================

function Write-Log {
    param([string]$Message, [ValidateSet("INFO","SUCCESS","WARN","ERROR","HEADER","DEBUG")]$Level = "INFO")

    $colors = @{
        INFO = 'Cyan'
        SUCCESS = 'Green'
        WARN = 'Yellow'
        ERROR = 'Red'
        HEADER = 'Magenta'
        DEBUG = 'DarkCyan'
    }

    $icons = @{
        INFO = '>'
        SUCCESS = '+'
        WARN = '!'
        ERROR = 'X'
        HEADER = '~'
        DEBUG = '#'
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "  [$timestamp] " -ForegroundColor $UIConfig.DarkNeutral -NoNewline
    Write-Host "$($icons[$Level]) " -ForegroundColor $colors[$Level] -NoNewline
    Write-Host "$Message" -ForegroundColor $colors[$Level]
}

function Write-Header {
    param([string]$Text, [int]$Width = 80)

    Write-Host ""
    Write-Host "  +$('=' * ($Width - 4))+" -ForegroundColor $UIConfig.Primary
    Write-Host "  |  $($Text.PadRight($Width - 6))|" -ForegroundColor $UIConfig.Primary
    Write-Host "  +$('=' * ($Width - 4))+" -ForegroundColor $UIConfig.Primary
    Write-Host ""
}

function Write-Section {
    param([string]$Text, [int]$Width = 80)

    Write-Host "  +$('-' * ($Width - 4))+" -ForegroundColor $UIConfig.Primary
    Write-Host "  |  $($Text.PadRight($Width - 6))|" -ForegroundColor $UIConfig.Primary
    Write-Host "  +$('-' * ($Width - 4))+" -ForegroundColor $UIConfig.Primary
}

function Write-Divider {
    param([int]$Width = 80)
    Write-Host "  $('-' * $Width)" -ForegroundColor $UIConfig.DarkNeutral
}

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  $('-' * 78)" -ForegroundColor $UIConfig.Accent
    Write-Host ""
    Write-Host "      +===============================================================+" -ForegroundColor $UIConfig.Accent
    Write-Host "      |                                                               |" -ForegroundColor $UIConfig.Accent
    Write-Host "      |          *  GPU VIRTUALIZATION MANAGER  v3.0  *              |" -ForegroundColor $UIConfig.Accent
    Write-Host "      |                                                               |" -ForegroundColor $UIConfig.Accent
    Write-Host "      |      Unified Hyper-V Manager with GPU Partition Support      |" -ForegroundColor $UIConfig.Accent
    Write-Host "      |                                                               |" -ForegroundColor $UIConfig.Accent
    Write-Host "      +===============================================================+" -ForegroundColor $UIConfig.Accent
    Write-Host ""
    Write-Host "  $('-' * 78)" -ForegroundColor $UIConfig.Accent
    Write-Host ""
}

function Select-MenuItem {
    param(
        [string[]]$Items,
        [int]$DefaultIndex = 0
    )

    $selected = $DefaultIndex
    $items_count = $Items.Count
    $lastSelected = -1

    Show-Banner
    Write-Host "  > MAIN MENU" -ForegroundColor $UIConfig.Primary
    Write-Host "  |" -ForegroundColor $UIConfig.Primary
    Write-Host "  |  (Use UP/DOWN arrows to navigate, ENTER to select)" -ForegroundColor $UIConfig.DarkNeutral
    Write-Host "  |" -ForegroundColor $UIConfig.Primary

    $menuStartLine = [Console]::CursorTop

    for ($i = 0; $i -lt $items_count; $i++) {
        Write-Host "  |     $($Items[$i])" -ForegroundColor White
    }

    Write-Host "  |" -ForegroundColor $UIConfig.Primary
    Write-Host "  >$('=' * 76)" -ForegroundColor $UIConfig.Primary
    Write-Host ""

    while ($true) {
        if ($selected -ne $lastSelected) {
            if ($lastSelected -ge 0) {
                [Console]::SetCursorPosition(0, $menuStartLine + $lastSelected)
                Write-Host "  |     $($Items[$lastSelected])" -ForegroundColor White
            }

            [Console]::SetCursorPosition(0, $menuStartLine + $selected)
            Write-Host "  |  >> $($Items[$selected])" -ForegroundColor $UIConfig.Success

            $lastSelected = $selected
        }

        $key = [System.Console]::ReadKey($true)

        if ($key.Key -eq "UpArrow") {
            $selected = ($selected - 1) % $items_count
            if ($selected -lt 0) { $selected = $items_count - 1 }
        } elseif ($key.Key -eq "DownArrow") {
            $selected = ($selected + 1) % $items_count
        } elseif ($key.Key -eq "Enter") {
            [Console]::SetCursorPosition(0, $menuStartLine + $items_count + 2)
            return $selected
        }
    }
}

function Select-PresetMenu {
    param()

    $presets = @(
        "Gaming       | 16GB RAM, 8 CPU, 256GB Storage",
        "Development | 8GB RAM, 4 CPU, 128GB Storage",
        "ML Training  | 32GB RAM, 12 CPU, 512GB Storage",
        "Custom Configuration"
    )

    $selected = 0
    $lastSelected = -1

    Clear-Host
    Write-Header "VIRTUAL MACHINE CONFIGURATION"

    Write-Host "  > QUICK PRESETS" -ForegroundColor $UIConfig.Primary
    Write-Host "  |" -ForegroundColor $UIConfig.Primary
    Write-Host "  |  (Use UP/DOWN arrows to navigate, ENTER to select)" -ForegroundColor $UIConfig.DarkNeutral
    Write-Host "  |" -ForegroundColor $UIConfig.Primary

    $menuStartLine = [Console]::CursorTop

    for ($i = 0; $i -lt $presets.Count; $i++) {
        Write-Host "  |     $($presets[$i])" -ForegroundColor White
    }

    Write-Host "  |" -ForegroundColor $UIConfig.Primary
    Write-Host "  >$('=' * 76)" -ForegroundColor $UIConfig.Primary
    Write-Host ""

    while ($true) {
        if ($selected -ne $lastSelected) {
            if ($lastSelected -ge 0) {
                [Console]::SetCursorPosition(0, $menuStartLine + $lastSelected)
                Write-Host "  |     $($presets[$lastSelected])" -ForegroundColor White
            }

            [Console]::SetCursorPosition(0, $menuStartLine + $selected)
            Write-Host "  |  >> $($presets[$selected])" -ForegroundColor $UIConfig.Success

            $lastSelected = $selected
        }

        $key = [System.Console]::ReadKey($true)

        if ($key.Key -eq "UpArrow") {
            $selected = ($selected - 1) % $presets.Count
            if ($selected -lt 0) { $selected = $presets.Count - 1 }
        } elseif ($key.Key -eq "DownArrow") {
            $selected = ($selected + 1) % $presets.Count
        } elseif ($key.Key -eq "Enter") {
            [Console]::SetCursorPosition(0, $menuStartLine + $presets.Count + 2)
            return $selected
        }
    }
}

function Get-QuickConfig {
    $presetData = @(
        @{Name="Gaming-VM";RAM=16;CPU=8;Storage=256},
        @{Name="Dev-VM";RAM=8;CPU=4;Storage=128},
        @{Name="ML-VM";RAM=32;CPU=12;Storage=512}
    )

    $choice = Select-PresetMenu

    if ($choice -lt 3) {
        $preset = $presetData[$choice]
        Write-Host ""
        $name = Read-Host "  VM Name (default: $($preset.Name))"
        Write-Host ""
        $iso = Read-Host "  ISO Path (Enter to skip)"
        Write-Host ""

        return @{
            Name = if($name){$name}else{$preset.Name}
            RAM = $preset.RAM
            CPU = $preset.CPU
            Storage = $preset.Storage
            Path = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
            ISO = $iso
        }
    }

    Write-Header "CUSTOM VIRTUAL MACHINE CONFIGURATION"
    Write-Host ""

    $name = Read-Host "  VM Name"
    $ram = [int](Read-Host "  RAM in GB (minimum 2)")
    $cpu = [int](Read-Host "  CPU Cores")
    $storage = [int](Read-Host "  Storage in GB")
    $iso = Read-Host "  ISO Path (Enter to skip)"

    Write-Host ""

    return @{
        Name = $name
        RAM = $ram
        CPU = $cpu
        Storage = $storage
        Path = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
        ISO = $iso
    }
}

function Show-LoadingSpinner {
    param([string]$Message, [int]$Duration = 2)

    $spinner = @('|', '/', '-', '\')
    $elapsed = 0

    while ($elapsed -lt $Duration) {
        foreach ($char in $spinner) {
            Write-Host "`r  $char $Message" -ForegroundColor $UIConfig.Primary -NoNewline
            Start-Sleep -Milliseconds 150
            $elapsed += 0.15
            if ($elapsed -ge $Duration) { break }
        }
    }
    Write-Host "`r  + $Message" -ForegroundColor $UIConfig.Success
}

function Initialize-VM {
    param($Config)

    Write-Header "CREATING VIRTUAL MACHINE"
    Write-Log "VM Name: $($Config.Name)" "INFO"
    Write-Log "RAM: $($Config.RAM)GB | CPU: $($Config.CPU) Cores | Storage: $($Config.Storage)GB" "INFO"
    Write-Host ""

    $vhdPath = Join-Path $Config.Path "$($Config.Name).vhdx"

    if (Get-VM $Config.Name -EA SilentlyContinue) {
        Write-Log "VM already exists" "ERROR"
        return $null
    }

    if (Test-Path $vhdPath) {
        $overwrite = Read-Host "  VHDX exists. Overwrite? (Y/N)"
        if ($overwrite -match "^[Yy]$") {
            Remove-Item $vhdPath -Force
        } else { 
            Write-Log "Operation cancelled" "WARN"
            return $null 
        }
    }

    try {
        Show-LoadingSpinner "Creating VM configuration..." 2

        $ram = [int64]$Config.RAM * 1GB
        $storage = [int64]$Config.Storage * 1GB

        New-Item -ItemType Directory -Path $Config.Path -Force -EA SilentlyContinue | Out-Null
        New-VM -Name $Config.Name -MemoryStartupBytes $ram -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes $storage | Out-Null

        Show-LoadingSpinner "Configuring processor and memory..." 1
        Set-VMProcessor $Config.Name -Count $Config.CPU
        Set-VMMemory $Config.Name -DynamicMemoryEnabled $false

        Show-LoadingSpinner "Applying security settings..." 1
        Set-VM $Config.Name -CheckpointType Disabled -AutomaticStopAction ShutDown -AutomaticStartAction Nothing
        Set-VM $Config.Name -AutomaticCheckpointsEnabled $false
        Set-VMHost -EnableEnhancedSessionMode $false

        Show-LoadingSpinner "Disabling integration services..." 1
        Disable-VMIntegrationService $Config.Name -Name "Guest Service Interface"
        Disable-VMIntegrationService $Config.Name -Name "VSS"

        Show-LoadingSpinner "Finalizing VM setup..." 1
        Stop-VM $Config.Name -Force -EA SilentlyContinue
        while ((Get-VM $Config.Name).State -ne "Off") { Start-Sleep -Milliseconds 500 }

        Set-VMFirmware $Config.Name -EnableSecureBoot On
        Set-VMKeyProtector $Config.Name -NewLocalKeyProtector
        Enable-VMTPM $Config.Name

        if ($Config.ISO -and (Test-Path $Config.ISO)) {
            Add-VMDvdDrive $Config.Name -Path $Config.ISO
            $dvd = Get-VMDvdDrive $Config.Name
            $hdd = Get-VMHardDiskDrive $Config.Name
            if ($dvd -and $hdd) {
                Set-VMFirmware $Config.Name -BootOrder $dvd, $hdd
                Write-Log "Boot order configured: DVD first" "SUCCESS"
            }
            Write-Log "ISO attached successfully" "SUCCESS"
        }

        Write-Host ""
        Write-Section "VM CREATED SUCCESSFULLY" 80
        Write-Log "VM: $($Config.Name)" "SUCCESS"
        Write-Log "RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "SUCCESS"
        Write-Host ""

        return $Config.Name
    } catch {
        Write-Log "Creation failed: $_" "ERROR"
        return $null
    }
}

function Set-GPUPartition {
    param([string]$VMName, [int]$Percentage = 0)

    if (!$VMName) { 
        Write-Header "GPU PARTITION CONFIGURATION"
        $VMName = Read-Host "  Enter VM Name" 
    }

    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }

    if ($Percentage -eq 0) {
        Write-Host ""
        $Percentage = [int](Read-Host "  GPU Allocation Percentage (1-100)")
    }

    $Percentage = [Math]::Max(1, [Math]::Min(100, $Percentage))

    Write-Header "CONFIGURING GPU PARTITION"
    Write-Log "Target VM: $VMName" "INFO"
    Write-Log "Allocation: $Percentage%" "INFO"
    Write-Host ""

    if ($vm.State -ne "Off") {
        Show-LoadingSpinner "Shutting down VM..." 1
    }

    try {
        Show-LoadingSpinner "Removing existing GPU adapters..." 1
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter

        Show-LoadingSpinner "Adding GPU partition adapter..." 1
        Add-VMGpuPartitionAdapter $VMName

        Show-LoadingSpinner "Allocating GPU resources..." 1
        $max = [int](($Percentage / 100) * 1000000000)
        $opt = $max - 1

        Set-VMGpuPartitionAdapter $VMName `
            -MinPartitionVRAM 1 -MaxPartitionVRAM $max -OptimalPartitionVRAM $opt `
            -MinPartitionEncode 1 -MaxPartitionEncode $max -OptimalPartitionEncode $opt `
            -MinPartitionDecode 1 -MaxPartitionDecode $max -OptimalPartitionDecode $opt `
            -MinPartitionCompute 1 -MaxPartitionCompute $max -OptimalPartitionCompute $opt

        Show-LoadingSpinner "Applying memory mapping..." 1
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB

        Write-Host ""
        Write-Section "GPU PARTITION CONFIGURED" 80
        Write-Log "GPU Allocation: $Percentage%" "SUCCESS"
        Write-Log "VM: $VMName" "SUCCESS"
        Write-Host ""

        return $true
    } catch {
        Write-Log "GPU configuration failed: $_" "ERROR"
        return $false
    }
}

function Install-GPUDrivers {
    param([string]$VMName)

    if (!$VMName) { 
        Write-Header "INSTALLING GPU DRIVERS"
        $VMName = Read-Host "  Enter VM Name" 
    }

    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }

    $vhd = (Get-VMHardDiskDrive $VMName).Path
    if (!$vhd) {
        Write-Log "No VHD found" "ERROR"
        return $false
    }

    Write-Header "INSTALLING GPU DRIVERS"
    Write-Log "Target VM: $VMName" "INFO"
    Write-Host ""

    if ($vm.State -ne "Off") {
        Show-LoadingSpinner "Shutting down VM..." 1
    }

    try {
        Show-LoadingSpinner "Scanning for NVIDIA drivers on host..." 2

        $hostDrivers = Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory -EA SilentlyContinue |
            Where-Object { $_.Name -like "nv_dispi.inf_amd64*" } | Sort-Object Name -Descending

        $hostFiles = Get-ChildItem "C:\Windows\System32" -File | Where-Object { $_.Name -like "nv*" }

        if (!$hostDrivers -or !$hostFiles) {
            Write-Log "No NVIDIA drivers found on host" "ERROR"
            return $false
        }

        Write-Log "Found $($hostDrivers.Count) driver repos, $($hostFiles.Count) system files" "SUCCESS"
        Write-Host ""

        $mountPoint = "C:\Temp\VMMount_$(Get-Random)"
        $mounted = $null
        $partition = $null

        Show-LoadingSpinner "Mounting virtual disk..." 2
        $mounted = Mount-VHD $vhd -NoDriveLetter -PassThru -EA Stop
        Start-Sleep -Seconds 2

        Update-Disk $mounted.DiskNumber -EA SilentlyContinue

        try {
            $partition = Get-Partition -DiskNumber $mounted.DiskNumber -EA Stop | 
                Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        } catch {
            Write-Host ""
            Write-Section "ERROR: WINDOWS NOT INSTALLED" 80
            Write-Log "Windows is not installed on this VM" "ERROR"
            Write-Host ""
            Write-Log "Resolution steps:" "WARN"
            Write-Host "  1. Start the VM and boot from the ISO" -ForegroundColor $UIConfig.Warning
            Write-Host "  2. Install Windows on the virtual hard disk" -ForegroundColor $UIConfig.Warning
            Write-Host "  3. Complete Windows setup and shut down the VM" -ForegroundColor $UIConfig.Warning
            Write-Host "  4. Run this driver injection again (option 3)" -ForegroundColor $UIConfig.Warning
            Write-Host ""
            return $false
        }

        if (!$partition) {
            Write-Host ""
            Write-Section "ERROR: NO VALID PARTITION FOUND" 80
            Write-Log "The VHD does not contain a valid Windows installation" "ERROR"
            Write-Host ""
            return $false
        }

        Show-LoadingSpinner "Mounting partition..." 1
        New-Item $mountPoint -ItemType Directory -Force | Out-Null
        Add-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint

        if (!(Test-Path "$mountPoint\Windows")) {
            Write-Host ""
            Write-Section "ERROR: WINDOWS DIRECTORY NOT FOUND" 80
            Write-Log "Partition mounted but Windows folder not detected" "ERROR"
            Write-Host ""
            return $false
        }

        Show-LoadingSpinner "Removing old NVIDIA drivers from VM..." 1
        $oldDriverPath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
        if (Test-Path $oldDriverPath) {
            Get-ChildItem $oldDriverPath -Directory | Where-Object { $_.Name -like "nv_dispi*" } | Remove-Item -Recurse -Force -EA SilentlyContinue
        }
        Get-ChildItem "$mountPoint\Windows\System32" -File | Where-Object { $_.Name -like "nv*" } | Remove-Item -Force -EA SilentlyContinue

        Show-LoadingSpinner "Injecting NVIDIA drivers into VM..." 2
        $destDriver = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
        New-Item $destDriver -ItemType Directory -Force -EA SilentlyContinue | Out-Null

        foreach ($driver in $hostDrivers) {
            Copy-Item $driver.FullName -Destination $destDriver -Recurse -Force
            Write-Log "Copied: $($driver.Name)" "SUCCESS"
        }

        foreach ($file in $hostFiles) {
            Copy-Item $file.FullName -Destination "$mountPoint\Windows\System32" -Force -EA SilentlyContinue
        }

        Write-Host ""
        Write-Section "DRIVER INJECTION COMPLETE" 80
        Write-Log "Successfully injected $($hostDrivers.Count) driver repos" "SUCCESS"
        Write-Log "Successfully copied $($hostFiles.Count) system files" "SUCCESS"
        Write-Host ""

        return $true

    } catch {
        Write-Host ""
        Write-Section "ERROR: DRIVER INJECTION FAILED" 80
        Write-Log "Error: $_" "ERROR"
        Write-Host ""
        return $false
    } finally {
        if ($mounted -and $partition) {
            Remove-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint -EA SilentlyContinue
        }
        if ($mounted) {
            Dismount-VHD $vhd -EA SilentlyContinue
        }
        Remove-Item $mountPoint -Recurse -Force -EA SilentlyContinue
    }
}

function Copy-VMAppsToDownloads {
    Write-Header "COPYING VM APPLICATIONS"

    $VMName = Read-Host "  Enter VM Name"
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }

    $vhd = (Get-VMHardDiskDrive $VMName).Path
    if (!$vhd) {
        Write-Log "No VHD found for VM: $VMName" "ERROR"
        return $false
    }

    $scriptPath = Split-Path -Parent $PSCommandPath
    $vmAppsFolder = Join-Path $scriptPath "VM Apps"

    if (!(Test-Path $vmAppsFolder)) {
        Write-Log "VM Apps folder not found at: $vmAppsFolder" "ERROR"
        Write-Log "Create a 'VM Apps' folder in the script directory with zip files" "WARN"
        return $false
    }

    $zipFiles = @(Get-ChildItem $vmAppsFolder -Filter "*.zip" -File)

    if ($zipFiles.Count -eq 0) {
        Write-Log "No zip files found in VM Apps folder" "WARN"
        return $false
    }

    Write-Log "Found $($zipFiles.Count) application(s) to copy" "INFO"
    Write-Host ""

    if ($vm.State -ne "Off") {
        Show-LoadingSpinner "Shutting down VM..." 1
    }

    $mountPoint = "C:\Temp\VMMount_$(Get-Random)"
    $mounted = $null
    $partition = $null

    try {
        Show-LoadingSpinner "Mounting VM virtual disk..." 2
        $mounted = Mount-VHD $vhd -NoDriveLetter -PassThru -EA Stop
        Start-Sleep -Seconds 2

        Update-Disk $mounted.DiskNumber -EA SilentlyContinue

        try {
            $partition = Get-Partition -DiskNumber $mounted.DiskNumber -EA Stop | 
                Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        } catch {
            Write-Log "WINDOWS IS NOT INSTALLED ON THIS VM" "ERROR"
            return $false
        }

        if (!$partition) {
            Write-Log "NO VALID PARTITION FOUND" "ERROR"
            return $false
        }

        Show-LoadingSpinner "Mounting partition..." 1
        New-Item $mountPoint -ItemType Directory -Force | Out-Null
        Add-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint

        if (!(Test-Path "$mountPoint\Windows")) {
            Write-Log "WINDOWS DIRECTORY NOT FOUND" "ERROR"
            return $false
        }

        Show-LoadingSpinner "Detecting user account..." 1

        $userProfiles = @(Get-ChildItem "$mountPoint\Users" -Directory -EA SilentlyContinue | 
            Where-Object { $_.Name -notin @("Public", "Administrator", "Default", "Default.migrated") })

        if ($userProfiles.Count -eq 0) {
            Write-Log "No user profile found in VM" "ERROR"
            Write-Log "Make sure Windows is fully installed with a user account" "WARN"
            return $false
        }

        $userProfile = $userProfiles[0]
        $userDownloads = "$mountPoint\Users\$($userProfile.Name)\Downloads"

        if (!(Test-Path $userDownloads)) {
            Show-LoadingSpinner "Creating Downloads folder..." 1
            New-Item $userDownloads -ItemType Directory -Force | Out-Null
        }

        $vmAppsDestination = "$userDownloads\VM Apps"
        Show-LoadingSpinner "Creating VM Apps folder..." 1
        New-Item $vmAppsDestination -ItemType Directory -Force | Out-Null

        Write-Log "Copying $($zipFiles.Count) application(s)..." "INFO"
        Write-Host ""

        $successCount = 0
        $failCount = 0

        foreach ($zipFile in $zipFiles) {
            try {
                Copy-Item $zipFile.FullName -Destination $vmAppsDestination -Force -EA Stop
                Write-Log "+ $($zipFile.Name)" "SUCCESS"
                $successCount++
            } catch {
                Write-Log "X $($zipFile.Name)" "WARN"
                $failCount++
            }
        }

        Write-Host ""
        Write-Section "VM APPS COPY COMPLETE" 80
        Write-Log "Successfully copied: $successCount / $($zipFiles.Count) files" "SUCCESS"
        if ($failCount -gt 0) {
            Write-Log "Failed files: $failCount" "WARN"
        }
        Write-Log "Location in VM: Users\$($userProfile.Name)\Downloads\VM Apps" "INFO"
        Write-Host ""

        return $true

    } catch {
        Write-Host ""
        Write-Section "ERROR: VM APPS COPY FAILED" 80
        Write-Log "Error: $_" "ERROR"
        Write-Host ""
        return $false
    } finally {
        if ($mounted -and $partition) {
            Remove-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint -EA SilentlyContinue
        }
        if ($mounted) {
            Dismount-VHD $vhd -EA SilentlyContinue
        }
        Remove-Item $mountPoint -Recurse -Force -EA SilentlyContinue
    }
}

function Invoke-CompleteSetup {
    Write-Log "Starting complete GPU VM setup..." "HEADER"

    $config = Get-QuickConfig
    $vmName = Initialize-VM -Config $config
    if (!$vmName) { return }

    Write-Log "Proceeding with GPU configuration..." "INFO"
    Write-Host ""
    $gpuPercent = [int](Read-Host "  GPU Allocation Percentage (default: 50)")
    if (!$gpuPercent) { $gpuPercent = 50 }

    if (!(Set-GPUPartition -VMName $vmName -Percentage $gpuPercent)) {
        Write-Log "GPU configuration failed" "ERROR"
        return
    }

    Write-Host ""
    Write-Section "COMPLETE SETUP FINISHED" 80
    Write-Log "VM '$vmName' ready with GPU partition" "SUCCESS"
    Write-Log "Next: Install OS and inject drivers (option 3)" "INFO"
    Write-Host ""
}

function Show-SystemInfo {
    Show-Banner

    Write-Header "HYPER-V VIRTUAL MACHINES"

    $vms = Get-VM | Select-Object Name, State, CPUUsage, @{N='RAM_GB';E={[math]::Round($_.MemoryAssigned/1GB,2)}}, @{N='GPU';E={(Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue) -ne $null}}

    if ($vms) {
        Write-Host "  > VM LIST" -ForegroundColor $UIConfig.Primary
        Write-Host "  |" -ForegroundColor $UIConfig.Primary

        foreach ($vm in $vms) {
            $gpuStatus = if ($vm.GPU) { "[GPU]" } else { "[-]" }
            $stateColor = if ($vm.State -eq "Running") { $UIConfig.Success } else { $UIConfig.Warning }
            $stateString = [string]$vm.State

            Write-Host "  |  " -ForegroundColor $UIConfig.Primary -NoNewline
            Write-Host "$($vm.Name.PadRight(20))" -ForegroundColor White -NoNewline
            Write-Host " | " -ForegroundColor $UIConfig.DarkNeutral -NoNewline
            Write-Host "$($stateString.PadRight(10))" -ForegroundColor $stateColor -NoNewline
            Write-Host " | " -ForegroundColor $UIConfig.DarkNeutral -NoNewline
            Write-Host "$($vm.RAM_GB)GB RAM" -ForegroundColor Cyan -NoNewline
            Write-Host " | " -ForegroundColor $UIConfig.DarkNeutral -NoNewline
            Write-Host $gpuStatus -ForegroundColor $UIConfig.Accent
        }

        Write-Host "  >$('=' * 76)" -ForegroundColor $UIConfig.Primary
    } else {
        Write-Log "No VMs found" "WARN"
    }

    Write-Host ""
    Write-Header "HOST GPU INFORMATION"

    $vramMB = $null
    try {
        $vramMB = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        if ($vramMB) {
            $vramGB = [math]::Round($vramMB / 1024, 2)
        }
    } catch {

    }

    $gpu = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" } | Select-Object -First 1
    if ($gpu) {
        Write-Host "  > GPU DETAILS" -ForegroundColor $UIConfig.Primary
        Write-Host "  |" -ForegroundColor $UIConfig.Primary

        Write-Host "  |  GPU Name     : " -ForegroundColor $UIConfig.Primary -NoNewline
        Write-Host $gpu.Name -ForegroundColor $UIConfig.Success

        Write-Host "  |  Driver Ver.  : " -ForegroundColor $UIConfig.Primary -NoNewline
        Write-Host $gpu.DriverVersion -ForegroundColor $UIConfig.Success

        Write-Host "  |  VRAM         : " -ForegroundColor $UIConfig.Primary -NoNewline
        if ($vramGB) {
            Write-Host "$vramGB GB" -ForegroundColor $UIConfig.Success
        } else {
            Write-Host "$([math]::Round($gpu.AdapterRAM/1GB,2)) GB" -ForegroundColor $UIConfig.Warning
        }

        Write-Host "  |  Status       : " -ForegroundColor $UIConfig.Primary -NoNewline
        Write-Host "+ Detected" -ForegroundColor $UIConfig.Success

        Write-Host "  >$('=' * 76)" -ForegroundColor $UIConfig.Primary
    } else {
        Write-Host "  > GPU STATUS" -ForegroundColor $UIConfig.Primary
        Write-Host "  |  " -NoNewline -ForegroundColor $UIConfig.Primary
        Write-Log "No NVIDIA GPU detected" "WARN"
        Write-Host "  >$('=' * 76)" -ForegroundColor $UIConfig.Primary
    }

    Write-Host ""
    Read-Host "  Press Enter to continue"
}

# ===============================================================================
#  MAIN EXECUTION
# ===============================================================================

$menuItems = @(
    "Create New VM",
    "Configure GPU Partition",
    "Inject GPU Drivers",
    "Complete Setup (VM + GPU + Drivers)",
    "Update VM Drivers",
    "List VMs & GPU Info",
    "Copy VM Apps to Downloads",
    "Exit"
)

$selectedIndex = 0

while ($true) {
    $selectedIndex = Select-MenuItem -Items $menuItems -DefaultIndex $selectedIndex
    Write-Host ""

    switch ($selectedIndex) {
        0 { 
            $config = Get-QuickConfig
            Initialize-VM -Config $config
            Read-Host "`n  Press Enter to continue"
        }
        1 { 
            Set-GPUPartition
            Read-Host "`n  Press Enter to continue"
        }
        2 { 
            Install-GPUDrivers
            Read-Host "`n  Press Enter to continue"
        }
        3 { 
            Invoke-CompleteSetup
            Read-Host "`n  Press Enter to continue"
        }
        4 { 
            Write-Log "Updating VM GPU drivers..." "HEADER"
            Install-GPUDrivers
            Read-Host "`n  Press Enter to continue"
        }
        5 { 
            Show-SystemInfo
        }
        6 {
            Copy-VMAppsToDownloads
            Read-Host "`n  Press Enter to continue"
        }
        7 { 
            Write-Log "Exiting GPU VM Manager..." "INFO"
            exit
        }
    }

    $selectedIndex = ($selectedIndex + 1) % $menuItems.Count
}

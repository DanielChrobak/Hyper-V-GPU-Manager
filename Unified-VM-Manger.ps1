# ==============================================================================
#  GPU Virtualization & Partitioning Tool v4.0
# ==============================================================================


# Request administrator privileges if not already running as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "`n  [!] Requesting administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}


# ==============================================================================
#  UTILITY FUNCTIONS
# ==============================================================================


function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{INFO='Cyan'; SUCCESS='Green'; WARN='Yellow'; ERROR='Red'; HEADER='Magenta'}
    $icons = @{INFO='>'; SUCCESS='+'; WARN='!'; ERROR='X'; HEADER='~'}
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "  [$timestamp] $($icons[$Level]) $Message" -ForegroundColor $colors[$Level]
}


function Write-Box {
    param([string]$Text, [string]$Style = "=", [int]$Width = 80)
    Write-Host ""
    Write-Host "  +$($Style * ($Width - 4))+" -ForegroundColor Cyan
    Write-Host "  |  $($Text.PadRight($Width - 6))|" -ForegroundColor Cyan
    Write-Host "  +$($Style * ($Width - 4))+" -ForegroundColor Cyan
    if ($Style -eq "=") { Write-Host "" }
}


function Show-Banner {
    Clear-Host
    Write-Host "`n  $('-' * 78)" -ForegroundColor Magenta
    Write-Host "      +===============================================================+" -ForegroundColor Magenta
    Write-Host "      |          *  GPU VIRTUALIZATION MANAGER  v4.0  *               |" -ForegroundColor Magenta
    Write-Host "      |    Smart Driver Detection & GPU Partition Support             |" -ForegroundColor Magenta
    Write-Host "      +===============================================================+" -ForegroundColor Magenta
    Write-Host "  $('-' * 78)`n" -ForegroundColor Magenta
}


function Select-Menu {
    param([string[]]$Items, [string]$Title = "MENU")
    $selected = 0
    $last = -1
    Show-Banner
    Write-Host "  > $Title" -ForegroundColor Cyan
    Write-Host "  |  (Use UP/DOWN arrows, ENTER to select)`n  |" -ForegroundColor DarkGray
    $menuStart = [Console]::CursorTop
    
    foreach ($item in $Items) { Write-Host "  |     $item" -ForegroundColor White }
    Write-Host "  |`n  >$('=' * 76)`n" -ForegroundColor Cyan
    
    while ($true) {
        # Redraw selected item
        if ($selected -ne $last) {
            if ($last -ge 0) {
                [Console]::SetCursorPosition(0, $menuStart + $last)
                Write-Host "  |     $($Items[$last])" -ForegroundColor White
            }
            [Console]::SetCursorPosition(0, $menuStart + $selected)
            Write-Host "  |  >> $($Items[$selected])" -ForegroundColor Green
            $last = $selected
        }
        
        # Handle keyboard input
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "UpArrow") { $selected = ($selected - 1 + $Items.Count) % $Items.Count }
        elseif ($key.Key -eq "DownArrow") { $selected = ($selected + 1) % $Items.Count }
        elseif ($key.Key -eq "Enter") { 
            [Console]::SetCursorPosition(0, $menuStart + $Items.Count + 2)
            return $selected 
        }
    }
}


function Select-VM {
    param([string]$Title = "SELECT VIRTUAL MACHINE", [bool]$AllowRunning = $false)
    
    Write-Box $Title
    
    # Get VMs based on filter
    if ($AllowRunning) {
        $vms = @(Get-VM)
    } else {
        $vms = @(Get-VM | Where-Object { $_.State -eq 'Off' })
    }
    
    if ($vms.Count -eq 0) {
        if ($AllowRunning) {
            Write-Log "No VMs found" "ERROR"
        } else {
            Write-Log "No stopped VMs found. VMs must be powered off for this operation." "ERROR"
        }
        Write-Host ""
        return $null
    }
    
    # Build menu items with VM info
    $menuItems = @()
    foreach ($vm in $vms) {
        $ram = if ($vm.MemoryAssigned -gt 0) { 
            [math]::Round($vm.MemoryAssigned / 1GB, 0) 
        } else { 
            [math]::Round($vm.MemoryStartup / 1GB, 0) 
        }
        
        $gpuAdapter = Get-VMGpuPartitionAdapter $vm.Name -EA SilentlyContinue
        $gpu = if ($gpuAdapter) { 
            "$([math]::Round(($gpuAdapter.MaxPartitionVRAM / 1000000000) * 100, 0))%" 
        } else { 
            "None" 
        }
        
        $state = $vm.State
        $menuItems += "$($vm.Name) | State: $state | RAM: ${ram}GB | CPU: $($vm.ProcessorCount) | GPU: $gpu"
    }
    
    $menuItems += "< Cancel >"
    
    $selection = Select-Menu -Items $menuItems -Title $Title
    
    # If user selected cancel
    if ($selection -eq $menuItems.Count - 1) {
        return $null
    }
    
    return $vms[$selection]
}


function Show-Spinner {
    param([string]$Message, [int]$Duration = 2)
    $spinner = @('|', '/', '-', '\')
    $elapsed = 0
    
    while ($elapsed -lt $Duration) {
        foreach ($char in $spinner) {
            Write-Host "`r  $char $Message" -ForegroundColor Cyan -NoNewline
            Start-Sleep -Milliseconds 150
            $elapsed += 0.15
            if ($elapsed -ge $Duration) { break }
        }
    }
    Write-Host "`r  + $Message" -ForegroundColor Green
}


function Stop-VMSafe {
    param([string]$VMName)
    $vm = Get-VM $VMName -EA SilentlyContinue
    
    # VM doesn't exist or is already off
    if (!$vm -or $vm.State -eq "Off") { return $true }
    
    Write-Host "`r  | Shutting down VM..." -ForegroundColor Cyan -NoNewline
    try {
        Stop-VM $VMName -Force -EA Stop
        $timeout = 0
        
        # Wait up to 60 seconds for graceful shutdown
        while ((Get-VM $VMName).State -ne "Off" -and $timeout -lt 60) {
            Start-Sleep -Milliseconds 500
            $timeout++
            $char = @('|', '/', '-', '\')[$timeout % 4]
            Write-Host "`r  $char Shutting down VM... ($timeout sec)" -ForegroundColor Cyan -NoNewline
        }
        
        # If still not off, force it
        if ((Get-VM $VMName).State -eq "Off") {
            Write-Host "`r  + VM shut down successfully            " -ForegroundColor Green
            Start-Sleep -Seconds 2
            return $true
        }
        
        Stop-VM $VMName -TurnOff -Force -EA Stop
        Start-Sleep -Seconds 3
        return $true
    } catch {
        Write-Host "`r  X Failed to stop VM: $_" -ForegroundColor Red
        return $false
    }
}


function Mount-VMDisk {
    param([string]$VHDPath)
    $mountPoint = "C:\Temp\VMMount_$(Get-Random)"
    New-Item $mountPoint -ItemType Directory -Force | Out-Null
    
    Show-Spinner "Mounting virtual disk..." 2
    $mounted = Mount-VHD $VHDPath -NoDriveLetter -PassThru -EA Stop
    Start-Sleep -Seconds 2
    Update-Disk $mounted.DiskNumber -EA SilentlyContinue
    
    # Find the largest partition (usually the Windows partition)
    $partition = Get-Partition -DiskNumber $mounted.DiskNumber -EA Stop | 
        Where-Object { $_.Size -gt 10GB } | 
        Sort-Object Size -Descending | 
        Select-Object -First 1
    
    if (!$partition) { throw "No valid partition found" }
    
    Show-Spinner "Mounting partition..." 1
    Add-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint
    
    if (!(Test-Path "$mountPoint\Windows")) { throw "Windows directory not found" }
    
    return @{Mounted=$mounted; Partition=$partition; MountPoint=$mountPoint}
}


function Dismount-VMDisk {
    param($MountInfo, [string]$VHDPath)
    if ($MountInfo.Mounted -and $MountInfo.Partition) {
        Remove-PartitionAccessPath -DiskNumber $MountInfo.Mounted.DiskNumber -PartitionNumber $MountInfo.Partition.PartitionNumber -AccessPath $MountInfo.MountPoint -EA SilentlyContinue
    }
    if ($VHDPath) { Dismount-VHD $VHDPath -EA SilentlyContinue }
    if ($MountInfo.MountPoint) { Remove-Item $MountInfo.MountPoint -Recurse -Force -EA SilentlyContinue }
}


function Select-GPUDevice {
    Write-Box "SELECT GPU DEVICE"
    
    # Get all display adapters
    $gpuDrivers = Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" }
    
    if ($gpuDrivers.Count -eq 0) {
        Write-Log "No display adapters found" "ERROR"
        return $null
    }
    
    $gpuList = @()
    $index = 1
    
    Write-Host ""
    foreach ($gpu in $gpuDrivers) {
        $gpuList += $gpu
        Write-Host "  [$index] $($gpu.DeviceName)" -ForegroundColor Green
        Write-Host "      Provider: $($gpu.DriverProviderName) | Version: $($gpu.DriverVersion)" -ForegroundColor DarkGray
        $index++
    }
    Write-Host ""
    
    # Get user selection
    do {
        $selection = Read-Host "  Enter GPU number (1-$($gpuList.Count))"
        $selectionNum = [int]$selection
    } while ($selectionNum -lt 1 -or $selectionNum -gt $gpuList.Count)
    
    return $gpuList[$selectionNum - 1]
}


function Get-DriverFiles {
    param([Object]$GPU)
    
    Write-Box "ANALYZING GPU DRIVERS" "-"
    Write-Log "GPU: $($GPU.DeviceName)" "INFO"
    Write-Log "Provider: $($GPU.DriverProviderName)" "INFO"
    Write-Log "Version: $($GPU.DriverVersion)" "INFO"
    Write-Host ""
    
    # Find the INF file from registry
    Show-Spinner "Finding INF file from registry..." 1
    
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $driverSubkeys = Get-ChildItem -Path $registryPath -EA SilentlyContinue
    
    $infFileName = $null
    $foundInRegistry = $false
    
    # Search registry for matching device
    foreach ($subkey in $driverSubkeys) {
        $props = Get-ItemProperty -Path $subkey.PSPath -EA SilentlyContinue
        
        if ($props.MatchingDeviceId) {
            $deviceIdFromReg = $props.MatchingDeviceId
            
            if ($GPU.DeviceID -like "*$deviceIdFromReg*" -or $deviceIdFromReg -like "*$($GPU.DeviceID)*") {
                $infFileName = $props.InfPath
                Write-Log "Found INF: $infFileName" "SUCCESS"
                $foundInRegistry = $true
                break
            }
        }
    }
    
    if (-not $foundInRegistry) {
        Write-Log "Could not find GPU in registry" "ERROR"
        return $null
    }
    
    # Read the INF file
    $infFilePath = "C:\Windows\INF\$infFileName"
    
    if (-not (Test-Path $infFilePath)) {
        Write-Log "INF file not found: $infFilePath" "ERROR"
        return $null
    }
    
    Show-Spinner "Reading INF file..." 1
    $infContent = Get-Content $infFilePath -Raw
    
    # Extract file references from INF
    Show-Spinner "Parsing INF for file references..." 1
    
    $filePatterns = @(
        '[\w\-\.]+\.sys',
        '[\w\-\.]+\.dll',
        '[\w\-\.]+\.exe',
        '[\w\-\.]+\.cat',
        '[\w\-\.]+\.inf',
        '[\w\-\.]+\.bin',
        '[\w\-\.]+\.vp',
        '[\w\-\.]+\.cpa'
    )
    
    $referencedFiles = @()
    
    foreach ($pattern in $filePatterns) {
        $matches = [regex]::Matches($infContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        foreach ($match in $matches) {
            if ($match.Value -and -not ($referencedFiles -contains $match.Value)) {
                $referencedFiles += $match.Value
            }
        }
    }
    
    Write-Log "Found $($referencedFiles.Count) file references in INF" "SUCCESS"
    Write-Host ""
    
    # Search for these files in system
    Show-Spinner "Locating files in system..." 2
    
    $foundFiles = @()
    $driverStoreFolders = @()
    
    $searchPaths = @(
        @{Path = "C:\Windows\System32\DriverStore\FileRepository"; Type = "DriverStore"; Recurse = $true}
        @{Path = "C:\Windows\System32"; Type = "System32"; Recurse = $false}
        @{Path = "C:\Windows\SysWow64"; Type = "SysWow64"; Recurse = $false}
    )
    
    foreach ($fileName in $referencedFiles) {
        $found = $false
        
        foreach ($searchPath in $searchPaths) {
            if ($found) { break }
            
            $searchArgs = @{
                Path = $searchPath.Path
                Filter = $fileName
                EA = 'SilentlyContinue'
            }
            
            if ($searchPath.Recurse) {
                $searchArgs['Recurse'] = $true
            }
            
            $result = Get-ChildItem @searchArgs | Select-Object -First 1
            
            if ($result) {
                $found = $true
                
                # Track DriverStore folders separately (they contain many files)
                if ($searchPath.Type -eq "DriverStore") {
                    $folderPath = $result.DirectoryName
                    
                    if ($folderPath -notin $driverStoreFolders) {
                        $driverStoreFolders += $folderPath
                    }
                } else {
                    # Individual system files
                    $foundFiles += [PSCustomObject]@{
                        FileName = $fileName
                        FullPath = $result.FullName
                        DestPath = $result.FullName.Replace("C:", "")
                    }
                }
            }
        }
    }
    
    Write-Log "Located $($foundFiles.Count) system files + $($driverStoreFolders.Count) DriverStore folder(s)" "SUCCESS"
    Write-Host ""
    
    return @{
        Files = $foundFiles
        StoreFolders = $driverStoreFolders
    }
}


function Get-VMConfig {
    # Preset configurations
    $presets = @(
        "Gaming       | 16GB RAM, 8 CPU,  256GB Storage",
        "Development  | 8GB RAM,  4 CPU,  128GB Storage",
        "ML Training  | 32GB RAM, 12 CPU, 512GB Storage",
        "Custom Configuration"
    )
    $presetData = @(
        @{Name="Gaming-VM"; RAM=16; CPU=8; Storage=256},
        @{Name="Dev-VM"; RAM=8; CPU=4; Storage=128},
        @{Name="ML-VM"; RAM=32; CPU=12; Storage=512}
    )
    
    $choice = Select-Menu -Items $presets -Title "VM CONFIGURATION"
    
    # Use preset or custom config
    if ($choice -lt 3) {
        $preset = $presetData[$choice]
        Write-Host ""
        $name = Read-Host "  VM Name (default: $($preset.Name))"
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
    
    # Custom configuration
    Write-Box "CUSTOM VM CONFIGURATION" "-"
    $name = Read-Host "  VM Name"
    $ram = [int](Read-Host "  RAM in GB")
    $cpu = [int](Read-Host "  CPU Cores")
    $storage = [int](Read-Host "  Storage in GB")
    $iso = Read-Host "  ISO Path (Enter to skip)"
    Write-Host ""
    
    return @{
        Name=$name
        RAM=$ram
        CPU=$cpu
        Storage=$storage
        Path="C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
        ISO=$iso
    }
}


# ==============================================================================
#  VM OPERATIONS
# ==============================================================================


function Initialize-VM {
    param($Config)
    Write-Box "CREATING VIRTUAL MACHINE"
    Write-Log "VM: $($Config.Name) | RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "INFO"
    Write-Host ""
    
    $vhdPath = Join-Path $Config.Path "$($Config.Name).vhdx"
    
    # Check if VM already exists
    if (Get-VM $Config.Name -EA SilentlyContinue) {
        Write-Log "VM already exists" "ERROR"
        return $null
    }
    
    # Check if VHDX already exists
    if (Test-Path $vhdPath) {
        if ((Read-Host "  VHDX exists. Overwrite? (Y/N)") -notmatch "^[Yy]$") {
            Write-Log "Operation cancelled" "WARN"
            return $null
        }
        Remove-Item $vhdPath -Force
    }
    
    try {
        # Create VM
        Show-Spinner "Creating VM configuration..." 2
        New-Item -ItemType Directory -Path $Config.Path -Force -EA SilentlyContinue | Out-Null
        New-VM -Name $Config.Name -MemoryStartupBytes ([int64]$Config.RAM * 1GB) -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes ([int64]$Config.Storage * 1GB) | Out-Null
        
        # Configure processor and memory
        Show-Spinner "Configuring processor and memory..." 1
        Set-VMProcessor $Config.Name -Count $Config.CPU
        Set-VMMemory $Config.Name -DynamicMemoryEnabled $false
        
        # Apply security settings
        Show-Spinner "Applying security settings..." 1
        Set-VM $Config.Name -CheckpointType Disabled -AutomaticStopAction ShutDown -AutomaticStartAction Nothing -AutomaticCheckpointsEnabled $false
        Set-VMHost -EnableEnhancedSessionMode $false
        Disable-VMIntegrationService $Config.Name -Name "Guest Service Interface", "VSS"
        
        # Finalize setup (TPM and Secure Boot)
        Show-Spinner "Finalizing setup..." 1
        Stop-VM $Config.Name -Force -EA SilentlyContinue
        while ((Get-VM $Config.Name).State -ne "Off") { Start-Sleep -Milliseconds 500 }
        
        Set-VMFirmware $Config.Name -EnableSecureBoot On
        Set-VMKeyProtector $Config.Name -NewLocalKeyProtector
        Enable-VMTPM $Config.Name
        
        # Attach ISO if provided
        if ($Config.ISO -and (Test-Path $Config.ISO)) {
            Add-VMDvdDrive $Config.Name -Path $Config.ISO
            $dvd = Get-VMDvdDrive $Config.Name
            $hdd = Get-VMHardDiskDrive $Config.Name
            if ($dvd -and $hdd) { Set-VMFirmware $Config.Name -BootOrder $dvd, $hdd }
            Write-Log "ISO attached" "SUCCESS"
        }
        
        Write-Host ""
        Write-Box "VM CREATED: $($Config.Name)" "-"
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
    
    # Select VM if not provided
    if (!$VMName) {
        $vm = Select-VM -Title "SELECT VM FOR GPU PARTITION" -AllowRunning $false
        if (!$vm) { return $false }
        $VMName = $vm.Name
    }
    
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }
    
    if ($Percentage -eq 0) {
        Write-Host ""
        $Percentage = [int](Read-Host "  GPU Allocation % (1-100)")
    }
    $Percentage = [Math]::Max(1, [Math]::Min(100, $Percentage))
    
    Write-Box "CONFIGURING GPU PARTITION"
    Write-Log "VM: $VMName | Allocation: $Percentage%" "INFO"
    Write-Host ""
    
    # Stop VM if running
    if ($vm.State -ne "Off" -and !(Stop-VMSafe -VMName $VMName)) {
        Write-Log "Failed to stop VM" "ERROR"
        return $false
    }
    
    try {
        Show-Spinner "Configuring GPU..." 2
        
        # Remove existing GPU adapter if present
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter
        
        # Add new GPU partition adapter
        Add-VMGpuPartitionAdapter $VMName
        
        # Calculate partition values
        $max = [int](($Percentage / 100) * 1000000000)
        $opt = $max - 1
        
        # Configure GPU partition
        Set-VMGpuPartitionAdapter $VMName -MinPartitionVRAM 1 -MaxPartitionVRAM $max -OptimalPartitionVRAM $opt -MinPartitionEncode 1 -MaxPartitionEncode $max -OptimalPartitionEncode $opt -MinPartitionDecode 1 -MaxPartitionDecode $max -OptimalPartitionDecode $opt -MinPartitionCompute 1 -MaxPartitionCompute $max -OptimalPartitionCompute $opt
        
        # Set VM memory mapping for GPU
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
        
        Write-Host ""
        Write-Box "GPU CONFIGURED: $Percentage%" "-"
        Write-Host ""
        return $true
    } catch {
        Write-Log "GPU config failed: $_" "ERROR"
        return $false
    }
}


function Install-GPUDrivers {
    param([string]$VMName)
    
    # Select VM if not provided
    if (!$VMName) {
        $vm = Select-VM -Title "SELECT VM FOR DRIVER INJECTION" -AllowRunning $false
        if (!$vm) { return $false }
        $VMName = $vm.Name
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
    
    Write-Box "AUTO-DETECT & INSTALL GPU DRIVERS"
    Write-Log "Target: $VMName" "INFO"
    Write-Host ""
    
    # Stop VM if running
    if ($vm.State -ne "Off" -and !(Stop-VMSafe -VMName $VMName)) {
        Write-Log "Failed to stop VM" "ERROR"
        return $false
    }
    
    try {
        # Select GPU and get driver files
        $selectedGPU = Select-GPUDevice
        if (!$selectedGPU) { return $false }
        
        Write-Host ""
        $driverData = Get-DriverFiles -GPU $selectedGPU
        if (!$driverData) { return $false }
        
        # Mount VM disk
        $mountInfo = Mount-VMDisk -VHDPath $vhd
        $mp = $mountInfo.MountPoint
        
        Show-Spinner "Preparing VM disk..." 1
        
        # Create HostDriverStore directory structure
        $hostDriverStorePath = "$mp\Windows\System32\HostDriverStore\FileRepository"
        New-Item -Path $hostDriverStorePath -ItemType Directory -Force -EA SilentlyContinue | Out-Null
        
        Write-Log "Copying $($driverData.StoreFolders.Count) DriverStore folders..." "INFO"
        Write-Host ""
        
        # Copy DriverStore folders to HostDriverStore
        foreach ($storeFolder in $driverData.StoreFolders) {
            $folderName = Split-Path -Leaf $storeFolder
            $destFolder = Join-Path $hostDriverStorePath $folderName
            
            try {
                Copy-Item -Path $storeFolder -Destination $destFolder -Recurse -Force -EA Stop
                $fileCount = @(Get-ChildItem -Path $destFolder -Recurse -File -EA SilentlyContinue).Count
                Write-Log "+ $folderName ($fileCount files)" "SUCCESS"
            } catch {
                Write-Log "! ${folderName}: $_" "WARN"
            }
        }
        
        Write-Host ""
        Write-Log "Copying $($driverData.Files.Count) system files..." "INFO"
        
        # Copy individual system files to their exact locations
        foreach ($file in $driverData.Files) {
            $destPath = "$mp$($file.DestPath)"
            $destDir = Split-Path -Parent $destPath
            
            try {
                New-Item -Path $destDir -ItemType Directory -Force -EA SilentlyContinue | Out-Null
                Copy-Item -Path $file.FullPath -Destination $destPath -Force -EA Stop
                Write-Log "+ $($file.FileName)" "SUCCESS"
            } catch {
                Write-Log "! $($file.FileName): $_" "WARN"
            }
        }
        
        Write-Host ""
        Write-Box "DRIVER INJECTION COMPLETE" "-"
        Write-Log "Injected $($driverData.Files.Count) files + $($driverData.StoreFolders.Count) folders to $VMName" "SUCCESS"
        Write-Host ""
        return $true
    } catch {
        if ($_.Exception.Message -match "partition") {
            Write-Log "Windows not installed on this VM" "ERROR"
            Write-Host "  Resolution: Install Windows first, then inject drivers`n" -ForegroundColor Yellow
        } else {
            Write-Log "Injection failed: $_" "ERROR"
        }
        return $false
    } finally {
        Dismount-VMDisk -MountInfo $mountInfo -VHDPath $vhd
    }
}


function Copy-VMApps {
    # Select VM
    $vm = Select-VM -Title "SELECT VM FOR APP COPY" -AllowRunning $false
    if (!$vm) { return $false }
    
    $VMName = $vm.Name
    
    $vhd = (Get-VMHardDiskDrive $VMName).Path
    if (!$vhd) {
        Write-Log "No VHD found" "ERROR"
        return $false
    }
    
    Write-Box "COPYING VM APPLICATIONS"
    Write-Log "Target: $VMName" "INFO"
    Write-Host ""
    
    # Check if VM Apps folder exists
    $vmAppsFolder = Join-Path (Split-Path -Parent $PSCommandPath) "VM Apps"
    if (!(Test-Path $vmAppsFolder)) {
        Write-Log "VM Apps folder not found" "ERROR"
        return $false
    }
    
    $zipFiles = @(Get-ChildItem $vmAppsFolder -Filter "*.zip" -File)
    if ($zipFiles.Count -eq 0) {
        Write-Log "No zip files found" "WARN"
        return $false
    }
    
    Write-Log "Found $($zipFiles.Count) app(s)" "INFO"
    Write-Host ""
    
    # Stop VM if running
    if ($vm.State -ne "Off" -and !(Stop-VMSafe -VMName $VMName)) {
        Write-Log "Failed to stop VM" "ERROR"
        return $false
    }
    
    try {
        # Mount VM disk
        $mountInfo = Mount-VMDisk -VHDPath $vhd
        $mp = $mountInfo.MountPoint
        
        # Find user account
        Show-Spinner "Detecting user account..." 1
        $userProfile = Get-ChildItem "$mp\Users" -Directory -EA SilentlyContinue | 
            Where-Object { $_.Name -notin @("Public", "Administrator", "Default", "Default.migrated") } | 
            Select-Object -First 1
        
        if (!$userProfile) {
            Write-Log "No user profile found" "ERROR"
            return $false
        }
        
        # Copy apps to Downloads folder
        $destPath = "$mp\Users\$($userProfile.Name)\Downloads\VM Apps"
        New-Item $destPath -ItemType Directory -Force | Out-Null
        
        Write-Log "Copying apps..." "INFO"
        $success = 0
        foreach ($zip in $zipFiles) {
            try {
                Copy-Item $zip.FullName -Destination $destPath -Force -EA Stop
                Write-Log "+ $($zip.Name)" "SUCCESS"
                $success++
            } catch {
                Write-Log "X $($zip.Name)" "WARN"
            }
        }
        
        Write-Host ""
        Write-Box "COPIED: $success/$($zipFiles.Count) files" "-"
        Write-Log "Location: Users\$($userProfile.Name)\Downloads\VM Apps" "INFO"
        Write-Host ""
        return $true
    } catch {
        Write-Log "Copy failed: $_" "ERROR"
        return $false
    } finally {
        Dismount-VMDisk -MountInfo $mountInfo -VHDPath $vhd
    }
}


function Invoke-CompleteSetup {
    Write-Log "Starting complete setup..." "HEADER"
    
    # Get VM configuration
    $config = Get-VMConfig
    $vmName = Initialize-VM -Config $config
    if (!$vmName) { return }
    
    # Get GPU allocation percentage
    Write-Host ""
    $gpuPercent = [int](Read-Host "  GPU Allocation % (default: 50)")
    if (!$gpuPercent) { $gpuPercent = 50 }
    
    if (!(Set-GPUPartition -VMName $vmName -Percentage $gpuPercent)) {
        Write-Log "GPU config failed" "ERROR"
        return
    }
    
    Write-Host ""
    Write-Box "SETUP COMPLETE: $vmName" "-"
    Write-Log "Next: Install OS and inject drivers (option 3)" "INFO"
    Write-Host ""
}


function Show-SystemInfo {
    Show-Banner
    Write-Box "HYPER-V VIRTUAL MACHINES"
    Write-Log "Gathering VM info..." "INFO"
    Write-Host ""
    
    $vms = @(Get-VM)
    if ($vms.Count -eq 0) {
        Write-Log "No VMs found" "WARN"
        Write-Host ""
        Read-Host "  Press Enter"
        return
    }
    
    # Display each VM's information
    foreach ($vm in $vms) {
        # Get VHD size
        $vhdSize = 0
        try {
            $vhdInfo = $vm.VMId | Get-VHD -EA SilentlyContinue
            if ($vhdInfo) { $vhdSize = [math]::Round($vhdInfo.Size / 1GB, 0) }
        } catch {}
        
        # Get RAM
        $ram = if ($vm.MemoryAssigned -gt 0) { 
            [math]::Round($vm.MemoryAssigned / 1GB, 0) 
        } else { 
            [math]::Round($vm.MemoryStartup / 1GB, 0) 
        }
        
        # Get GPU allocation
        $gpuAdapter = Get-VMGpuPartitionAdapter $vm.Name -EA SilentlyContinue
        $gpu = if ($gpuAdapter) { 
            "$([math]::Round(($gpuAdapter.MaxPartitionVRAM / 1000000000) * 100, 0))%" 
        } else { 
            "None" 
        }
        
        $stateColor = if ($vm.State -eq "Running") { "Green" } else { "Yellow" }
        
        Write-Host "  +$('-' * 76)" -ForegroundColor Cyan
        Write-Host "  |  VM: " -ForegroundColor Cyan -NoNewline
        Write-Host $vm.Name -ForegroundColor White
        Write-Host "  |  State: " -ForegroundColor Cyan -NoNewline
        Write-Host "$($vm.State) " -ForegroundColor $stateColor -NoNewline
        Write-Host "| RAM: " -ForegroundColor Cyan -NoNewline
        Write-Host "${ram}GB " -ForegroundColor Cyan -NoNewline
        Write-Host "| CPU: " -ForegroundColor Cyan -NoNewline
        Write-Host "$($vm.ProcessorCount) " -ForegroundColor Yellow -NoNewline
        Write-Host "| Storage: " -ForegroundColor Cyan -NoNewline
        Write-Host "${vhdSize}GB " -ForegroundColor Magenta -NoNewline
        Write-Host "| GPU: " -ForegroundColor Cyan -NoNewline
        Write-Host $gpu -ForegroundColor Magenta
        Write-Host "  +$('-' * 76)" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Box "HOST GPU INFORMATION"
    
    # Display all GPU info (universal - works with any GPU)
    $gpus = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    
    if ($gpus) {
        foreach ($gpu in $gpus) {
            Write-Host "  GPU: $($gpu.Name)" -ForegroundColor Green
            Write-Host "  Driver Version: $($gpu.DriverVersion)" -ForegroundColor Green
            Write-Host "  Driver Date: $($gpu.DriverDate)" -ForegroundColor Green
            
            # Display adapter RAM if available
            if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                $vramGB = [math]::Round($gpu.AdapterRAM / 1GB, 2)
                Write-Host "  VRAM: $vramGB GB" -ForegroundColor Green
            }
            
            # Display status
            $status = if ($gpu.Status -eq "OK") { "OK" } else { $gpu.Status }
            Write-Host "  Status: $status" -ForegroundColor $(if ($status -eq "OK") { "Green" } else { "Yellow" })
            
            Write-Host ""
        }
    } else {
        Write-Log "No discrete GPU detected" "WARN"
    }
    
    Read-Host "  Press Enter"
}

# ==============================================================================
#  MAIN MENU
# ==============================================================================


$menuItems = @(
    "Create New VM",
    "Configure GPU Partition",
    "Inject GPU Drivers (Auto-Detect)",
    "Complete Setup (VM + GPU + Drivers)",
    "Update VM Drivers (Auto-Detect)",
    "List VMs & GPU Info",
    "Copy VM Apps to Downloads",
    "Exit"
)


$selectedIndex = 0


while ($true) {
    $selectedIndex = Select-Menu -Items $menuItems -Title "MAIN MENU"
    Write-Host ""
    
    switch ($selectedIndex) {
        0 { Initialize-VM -Config (Get-VMConfig); Read-Host "`n  Press Enter" }
        1 { Set-GPUPartition; Read-Host "`n  Press Enter" }
        2 { Install-GPUDrivers; Read-Host "`n  Press Enter" }
        3 { Invoke-CompleteSetup; Read-Host "`n  Press Enter" }
        4 { Install-GPUDrivers; Read-Host "`n  Press Enter" }
        5 { Show-SystemInfo }
        6 { Copy-VMApps; Read-Host "`n  Press Enter" }
        7 { Write-Log "Exiting..." "INFO"; exit }
    }
    
    # Move to next menu item for convenience
    $selectedIndex = ($selectedIndex + 1) % $menuItems.Count
}



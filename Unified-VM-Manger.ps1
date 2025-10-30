# ===============================================================================
#  GPU Virtualization & Partitioning Tool v3.0
#  Unified Hyper-V Manager with GPU Partition Support
# ===============================================================================

#Requires -RunAsAdministrator

# ===============================================================================
#  CORE FUNCTIONS
# ===============================================================================

function Write-Log {
    param([string]$Message, [ValidateSet("INFO","SUCCESS","WARN","ERROR","HEADER")]$Level = "INFO")
    $colors = @{INFO='Cyan';SUCCESS='Green';WARN='Yellow';ERROR='Red';HEADER='Magenta'}
    $icons = @{INFO='[i]';SUCCESS='[+]';WARN='[!]';ERROR='[X]';HEADER='[>]'}
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp]" -ForegroundColor DarkGray -NoNewline
    Write-Host " $($icons[$Level]) " -ForegroundColor $colors[$Level] -NoNewline
    Write-Host $Message -ForegroundColor $colors[$Level]
}

function Show-Banner {
    Clear-Host
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "                                                                               " -ForegroundColor Cyan
    Write-Host "                    GPU VIRTUALIZATION MANAGER v3.0                            " -ForegroundColor Cyan
    Write-Host "              Unified Hyper-V Manager with GPU Partition Support               " -ForegroundColor Cyan
    Write-Host "                                                                               " -ForegroundColor Cyan
    Write-Host "===============================================================================" -ForegroundColor Cyan
}

function Show-Menu {
    Show-Banner
    Write-Host ""
    Write-Host "  [1] " -ForegroundColor Yellow -NoNewline; Write-Host "Create New VM" -ForegroundColor White
    Write-Host "  [2] " -ForegroundColor Yellow -NoNewline; Write-Host "Configure GPU Partition" -ForegroundColor White
    Write-Host "  [3] " -ForegroundColor Yellow -NoNewline; Write-Host "Inject GPU Drivers" -ForegroundColor White
    Write-Host "  [4] " -ForegroundColor Yellow -NoNewline; Write-Host "Complete Setup (VM + GPU + Drivers)" -ForegroundColor Green
    Write-Host "  [5] " -ForegroundColor Yellow -NoNewline; Write-Host "Update VM Drivers" -ForegroundColor White
    Write-Host "  [6] " -ForegroundColor Yellow -NoNewline; Write-Host "List VMs & GPU Info" -ForegroundColor Cyan
    Write-Host "  [0] " -ForegroundColor Red -NoNewline; Write-Host "Exit" -ForegroundColor White
    Write-Host ""
    Write-Host "-------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Get-QuickConfig {
    $presets = @{
        "1" = @{Name="Gaming-VM";RAM=16;CPU=8;Storage=256}
        "2" = @{Name="Dev-VM";RAM=8;CPU=4;Storage=128}
        "3" = @{Name="ML-VM";RAM=32;CPU=12;Storage=512}
    }
    
    Write-Host "`n Quick Presets:" -ForegroundColor Cyan
    Write-Host "  [1] Gaming - 16GB RAM, 8 CPU, 256GB Storage" -ForegroundColor White
    Write-Host "  [2] Development - 8GB RAM, 4 CPU, 128GB Storage" -ForegroundColor White
    Write-Host "  [3] Machine Learning - 32GB RAM, 12 CPU, 512GB Storage" -ForegroundColor White
    Write-Host "  [4] Custom Configuration" -ForegroundColor Yellow
    
    $choice = Read-Host "`n Select preset"
    if ($presets.ContainsKey($choice)) {
        $preset = $presets[$choice]
        $name = Read-Host "VM Name (default: $($preset.Name))"
        return @{
            Name = if($name){$name}else{$preset.Name}
            RAM = $preset.RAM
            CPU = $preset.CPU
            Storage = $preset.Storage
            Path = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
            ISO = Read-Host "ISO Path (Enter to skip)"
        }
    }
    
    # Custom config
    return @{
        Name = Read-Host "VM Name"
        RAM = [int](Read-Host "RAM in GB (minimum 2)")
        CPU = [int](Read-Host "CPU Cores")
        Storage = [int](Read-Host "Storage in GB")
        Path = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
        ISO = Read-Host "ISO Path (Enter to skip)"
    }
}

function Initialize-VM {
    param($Config)
    Write-Log "Initializing VM: $($Config.Name)" "HEADER"
    
    $vhdPath = Join-Path $Config.Path "$($Config.Name).vhdx"
    
    # Validation & Cleanup
    if (Get-VM $Config.Name -EA SilentlyContinue) {
        Write-Log "VM already exists" "ERROR"
        return $null
    }
    if (Test-Path $vhdPath) {
        if ((Read-Host "VHDX exists. Overwrite? (Y/N)") -match "^[Yy]$") {
            Remove-Item $vhdPath -Force
        } else { return $null }
    }
    
    # Create VM with optimized settings
    try {
        $ram = [int64]$Config.RAM * 1GB
        $storage = [int64]$Config.Storage * 1GB
        
        New-Item -ItemType Directory -Path $Config.Path -Force -EA SilentlyContinue | Out-Null
        New-VM -Name $Config.Name -MemoryStartupBytes $ram -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes $storage | Out-Null
        
        # Batch configuration
        Set-VMProcessor $Config.Name -Count $Config.CPU
        Set-VMMemory $Config.Name -DynamicMemoryEnabled $false
        Set-VM $Config.Name -CheckpointType Disabled -AutomaticStopAction ShutDown -AutomaticStartAction Nothing
        Set-VM $Config.Name -AutomaticCheckpointsEnabled $false
        Set-VMHost -EnableEnhancedSessionMode $false
        
        # Disable integration services
        Disable-VMIntegrationService $Config.Name -Name "Guest Service Interface"
        Disable-VMIntegrationService $Config.Name -Name "VSS"
        
        # Stop VM for firmware changes
        Stop-VM $Config.Name -Force -EA SilentlyContinue
        while ((Get-VM $Config.Name).State -ne "Off") { Start-Sleep -Milliseconds 500 }
        
        # Enable Secure Boot
        Set-VMFirmware $Config.Name -EnableSecureBoot On
        
        # TPM 2.0 (Windows 11 requirement)
        Set-VMKeyProtector $Config.Name -NewLocalKeyProtector
        Enable-VMTPM $Config.Name
        
        # ISO attachment and boot order
        if ($Config.ISO -and (Test-Path $Config.ISO)) {
            Add-VMDvdDrive $Config.Name -Path $Config.ISO
            
            # Set boot order: DVD first, then HDD
            $dvd = Get-VMDvdDrive $Config.Name
            $hdd = Get-VMHardDiskDrive $Config.Name
            if ($dvd -and $hdd) {
                Set-VMFirmware $Config.Name -BootOrder $dvd, $hdd
                Write-Log "Boot order configured: DVD first" "SUCCESS"
            }
            Write-Log "ISO attached" "SUCCESS"
        }
        
        Write-Log "VM created: $($Config.Name) | RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "SUCCESS"
        return $Config.Name
    } catch {
        Write-Log "Creation failed: $_" "ERROR"
        return $null
    }
}

function Set-GPUPartition {
    param([string]$VMName, [int]$Percentage = 0)
    
    if (!$VMName) { $VMName = Read-Host "VM Name" }
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }
    
    if ($Percentage -eq 0) {
        $Percentage = [int](Read-Host "GPU Allocation Percentage (1-100)")
    }
    $Percentage = [Math]::Max(1, [Math]::Min(100, $Percentage))
    
    # Auto-shutdown if needed
    if ($vm.State -ne "Off") {
        Write-Log "Shutting down VM..." "WARN"
        Stop-VM $VMName -Force
        while ((Get-VM $VMName).State -ne "Off") { Start-Sleep -Milliseconds 500 }
    }
    
    try {
        # Remove existing & add new
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter
        Add-VMGpuPartitionAdapter $VMName
        
        # Calculate partition values
        $max = [int](($Percentage / 100) * 1000000000)
        $opt = $max - 1
        
        # Apply GPU configuration
        Set-VMGpuPartitionAdapter $VMName `
            -MinPartitionVRAM 1 -MaxPartitionVRAM $max -OptimalPartitionVRAM $opt `
            -MinPartitionEncode 1 -MaxPartitionEncode $max -OptimalPartitionEncode $opt `
            -MinPartitionDecode 1 -MaxPartitionDecode $max -OptimalPartitionDecode $opt `
            -MinPartitionCompute 1 -MaxPartitionCompute $max -OptimalPartitionCompute $opt
        
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
        
        Write-Log "GPU configured: $Percentage% allocated to $VMName" "SUCCESS"
        return $true
    } catch {
        Write-Log "GPU configuration failed: $_" "ERROR"
        return $false
    }
}

function Install-GPUDrivers {
    param([string]$VMName)
    
    if (!$VMName) { $VMName = Read-Host "VM Name" }
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
    
    # Ensure VM is off
    if ($vm.State -ne "Off") {
        Write-Log "VM must be off. Shutting down..." "WARN"
        Stop-VM $VMName -Force
        while ((Get-VM $VMName).State -ne "Off") { Start-Sleep -Milliseconds 500 }
    }
    
    Write-Log "Scanning for NVIDIA drivers on host..." "INFO"
    
    # Locate host drivers
    $hostDrivers = Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory -EA SilentlyContinue |
        Where-Object { $_.Name -like "nv_dispi.inf_amd64*" } | Sort-Object Name -Descending
    
    $hostFiles = Get-ChildItem "C:\Windows\System32" -File | Where-Object { $_.Name -like "nv*" }
    
    if (!$hostDrivers -or !$hostFiles) {
        Write-Log "No NVIDIA drivers found on host" "ERROR"
        return $false
    }
    
    Write-Log "Found $($hostDrivers.Count) driver repos, $($hostFiles.Count) system files" "SUCCESS"
    
    $mountPoint = "C:\Temp\VMMount_$(Get-Random)"
    $mounted = $null
    $partition = $null
    
    try {
        # Mount VHD
        Write-Log "Mounting VHD..." "INFO"
        $mounted = Mount-VHD $vhd -NoDriveLetter -PassThru -EA Stop
        Start-Sleep -Seconds 2
        
        # Find Windows partition
        Update-Disk $mounted.DiskNumber -EA SilentlyContinue
        
        try {
            $partition = Get-Partition -DiskNumber $mounted.DiskNumber -EA Stop | 
                Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        } catch {
            Write-Host ""
            Write-Log "================================================" "ERROR"
            Write-Log "WINDOWS IS NOT INSTALLED ON THIS VM" "ERROR"
            Write-Log "================================================" "ERROR"
            Write-Host ""
            Write-Log "Steps to resolve:" "WARN"
            Write-Host "  1. Start the VM and boot from the ISO" -ForegroundColor Yellow
            Write-Host "  2. Install Windows on the virtual hard disk" -ForegroundColor Yellow
            Write-Host "  3. Complete Windows setup and shut down the VM" -ForegroundColor Yellow
            Write-Host "  4. Run this driver injection again (option 3)" -ForegroundColor Yellow
            Write-Host ""
            return $false
        }
        
        if (!$partition) {
            Write-Host ""
            Write-Log "================================================" "ERROR"
            Write-Log "NO VALID PARTITION FOUND" "ERROR"
            Write-Log "================================================" "ERROR"
            Write-Host ""
            Write-Log "The VHD does not contain a Windows installation" "ERROR"
            Write-Log "Please install Windows on the VM before injecting drivers" "WARN"
            Write-Host ""
            return $false
        }
        
        # Mount partition
        New-Item $mountPoint -ItemType Directory -Force | Out-Null
        Add-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint
        
        if (!(Test-Path "$mountPoint\Windows")) {
            Write-Host ""
            Write-Log "================================================" "ERROR"
            Write-Log "WINDOWS DIRECTORY NOT FOUND" "ERROR"
            Write-Log "================================================" "ERROR"
            Write-Host ""
            Write-Log "Partition mounted but no Windows folder detected" "ERROR"
            Write-Log "This VM requires a Windows installation before driver injection" "WARN"
            Write-Host ""
            return $false
        }
        
        # Clean old drivers
        Write-Log "Removing old NVIDIA drivers from VM..." "INFO"
        $oldDriverPath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
        if (Test-Path $oldDriverPath) {
            Get-ChildItem $oldDriverPath -Directory | Where-Object { $_.Name -like "nv_dispi*" } | Remove-Item -Recurse -Force -EA SilentlyContinue
        }
        Get-ChildItem "$mountPoint\Windows\System32" -File | Where-Object { $_.Name -like "nv*" } | Remove-Item -Force -EA SilentlyContinue
        
        # Copy new drivers
        Write-Log "Injecting NVIDIA drivers into VM..." "INFO"
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
        Write-Log "================================================" "SUCCESS"
        Write-Log "DRIVER INJECTION COMPLETE" "SUCCESS"
        Write-Log "================================================" "SUCCESS"
        Write-Log "Injected $($hostDrivers.Count) driver repos and $($hostFiles.Count) system files" "SUCCESS"
        Write-Host ""
        return $true
        
    } catch {
        Write-Host ""
        Write-Log "================================================" "ERROR"
        Write-Log "DRIVER INJECTION FAILED" "ERROR"
        Write-Log "================================================" "ERROR"
        Write-Log "Error: $_" "ERROR"
        Write-Host ""
        return $false
    } finally {
        # Cleanup
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
    $gpuPercent = [int](Read-Host "GPU Allocation Percentage (default: 50)")
    if (!$gpuPercent) { $gpuPercent = 50 }
    
    if (!(Set-GPUPartition -VMName $vmName -Percentage $gpuPercent)) {
        Write-Log "GPU configuration failed" "ERROR"
        return
    }
    
    Write-Log "VM '$vmName' ready with GPU partition. Install OS, then inject drivers (option 3)." "SUCCESS"
}

function Show-SystemInfo {
    Show-Banner
    Write-Host ""
    Write-Log "Hyper-V Virtual Machines:" "HEADER"
    
    $vms = Get-VM | Select-Object Name, State, CPUUsage, @{N='RAM_GB';E={[math]::Round($_.MemoryAssigned/1GB,2)}}, @{N='GPU';E={(Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue) -ne $null}}
    
    if ($vms) {
        $vms | Format-Table -AutoSize
    } else {
        Write-Log "No VMs found" "WARN"
    }
    
    Write-Host ""
    Write-Log "Host GPU Information:" "HEADER"
    
    # Try nvidia-smi first for accurate VRAM
    $vramMB = $null
    try {
        $vramMB = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        if ($vramMB) {
            $vramGB = [math]::Round($vramMB / 1024, 2)
        }
    } catch {
        # Fallback to WMI if nvidia-smi not available
    }
    
    $gpu = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" } | Select-Object -First 1
    if ($gpu) {
        Write-Host "  GPU: " -NoNewline -ForegroundColor Cyan
        Write-Host $gpu.Name -ForegroundColor White
        Write-Host "  Driver: " -NoNewline -ForegroundColor Cyan
        Write-Host $gpu.DriverVersion -ForegroundColor White
        Write-Host "  VRAM: " -NoNewline -ForegroundColor Cyan
        if ($vramGB) {
            Write-Host "$vramGB GB" -ForegroundColor White
        } else {
            Write-Host "$([math]::Round($gpu.AdapterRAM/1GB,2)) GB (limited by WMI)" -ForegroundColor Yellow
        }
    } else {
        Write-Log "No NVIDIA GPU detected" "WARN"
    }
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

# ===============================================================================
#  MAIN EXECUTION
# ===============================================================================

# Auto-elevate if not admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        "1" { 
            $config = Get-QuickConfig
            Initialize-VM -Config $config
            Read-Host "`nPress Enter to continue"
        }
        "2" { 
            Set-GPUPartition
            Read-Host "`nPress Enter to continue"
        }
        "3" { 
            Install-GPUDrivers
            Read-Host "`nPress Enter to continue"
        }
        "4" { 
            Invoke-CompleteSetup
            Read-Host "`nPress Enter to continue"
        }
        "5" { 
            Write-Log "Updating VM GPU drivers..." "HEADER"
            Install-GPUDrivers
            Read-Host "`nPress Enter to continue"
        }
        "6" { 
            Show-SystemInfo
        }
        "0" { 
            Write-Log "Exiting GPU VM Manager..." "INFO"
            exit
        }
        default { 
            Write-Log "Invalid selection" "WARN"
            Start-Sleep -Seconds 1
        }
    }
}

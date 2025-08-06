# Unified-VM-Manager.ps1 (Optimized Complete VM Management Suite)

function Log {
    param([string]$M, [string]$T = "INFO")
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))][$T] $M"
}

function Show-Menu {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host " UNIFIED VM MANAGER v2.0 " -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Create New VM" -ForegroundColor Green
    Write-Host "2. Create GPU Partition" -ForegroundColor Yellow
    Write-Host "3. Add GPU Drivers to VM" -ForegroundColor Magenta
    Write-Host "4. Complete GPU Setup (Create VM + GPU Partition + Drivers)" -ForegroundColor Red
    Write-Host "5. Update GPU Drivers in VM (overwrite)" -ForegroundColor Cyan
    Write-Host "6. Exit" -ForegroundColor Gray
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
}

function Setup-VMTPM {
    param([string]$VMName)
    try {
        Log "Setting up TPM for $VMName"
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (!$vm -or $vm.Generation -ne 2) {
            Log "VM not found or not Generation 2" "ERROR"
            return $false
        }
        if ($vm.State -ne "Off") {
            Log "Shutting down VM for TPM setup..."
            Stop-VM -Name $VMName -Force
            do { Start-Sleep 2 } while ((Get-VM -Name $VMName).State -ne "Off")
        }
        Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
        Enable-VMTPM -VMName $VMName
        return (Get-VMSecurity -VMName $VMName).TmpEnabled
    } catch {
        Log "TPM setup failed: $_" "ERROR"
        return $false
    }
}

function Get-VMConfig {
    if ((Read-Host "Use test values? (Y/N)") -match "^[Yy]$") {
        return @{
            Name = "TestVM"
            RAM = 8
            CPU = 4
            Storage = 128
            Path = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
            ISO = (Read-Host "ISO path")
        }
    }
    $config = @{}
    $config.Name = Read-Host "VM name"
    do { $config.RAM = [int](Read-Host "RAM (GB, min 2)") } while ($config.RAM -lt 2)
    do { $config.CPU = [int](Read-Host "CPU cores (min 1)") } while ($config.CPU -lt 1)
    do { $config.Storage = [int](Read-Host "Storage (GB, min 20)") } while ($config.Storage -lt 20)
    $defaultPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
    $userPath = Read-Host "VHD location (default: $defaultPath)"
    $config.Path = if ($userPath) { $userPath } else { $defaultPath }
    $config.ISO = Read-Host "ISO path"
    return $config
}

function Create-VM {
    Log "=== VM CREATION MODULE ===" "INFO"
    $config = Get-VMConfig
    $vhdPath = "$($config.Path)$($config.Name).vhdx"
    
    # Validation
    if (Get-VM -Name $config.Name -ErrorAction SilentlyContinue) {
        Log "VM '$($config.Name)' already exists" "ERROR"
        return $null
    }
    if (Test-Path $vhdPath) {
        if ((Read-Host "VHDX exists. Delete? (Y/N)") -match "^[Yy]$") {
            Remove-Item $vhdPath -Force
        } else { return $null }
    }
    if (!(Test-Path $config.Path)) { New-Item -ItemType Directory -Path $config.Path -Force | Out-Null }
    
    try {
        # Create VM with all settings
        $ramBytes = [int64]$config.RAM * 1GB
        $storageBytes = [int64]$config.Storage * 1GB
        Log "Creating VM: $($config.Name)"
        New-VM -Name $config.Name -MemoryStartupBytes $ramBytes -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes $storageBytes | Out-Null
        
        # Configure VM settings in one block
        Set-VMProcessor -VMName $config.Name -Count $config.CPU
        Set-VMMemory -VMName $config.Name -DynamicMemoryEnabled $false -StartupBytes $ramBytes
        Set-VM -Name $config.Name -CheckpointType Disabled
        Set-VMHost -EnableEnhancedSessionMode $false
        Disable-VMIntegrationService -VMName $config.Name -Name "Guest Service Interface"
        
        # TPM setup
        $tpmEnabled = Setup-VMTPM -VMName $config.Name
        
        # Attach ISO if exists
        $isoAttached = $false
        if (Test-Path $config.ISO) {
            Add-VMDvdDrive -VMName $config.Name -Path $config.ISO
            $isoAttached = $true
        }
        Log "VM '$($config.Name)' created successfully - RAM: $($config.RAM)GB, CPU: $($config.CPU), TPM: $tpmEnabled, ISO: $isoAttached" "SUCCESS"
        return $config.Name
    } catch {
        Log "VM creation failed: $_" "ERROR"
        return $null
    }
}

function Create-GPUPartition {
    param([string]$InputVMName = $null)
    Log "=== GPU PARTITION MODULE ===" "INFO"
    
    # Ensure we have a clean string for the VM name
    $vmName = if ($InputVMName) {
        # Convert any object to string and extract just the name
        $InputVMName.ToString()
    } else {
        Read-Host "Enter VM name"
    }
    
    if ([string]::IsNullOrWhiteSpace($vmName)) {
        Log "No VM name provided" "ERROR"
        return $false
    }
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (!$vm) { Log "VM '$vmName' not found" "ERROR"; return $false }
    
    do {
        $percentage = [int](Read-Host "Enter GPU percentage (1-100)")
    } while ($percentage -lt 1 -or $percentage -gt 100)
    
    # Ensure VM is off
    if ($vm.State -eq "Running") {
        if ((Read-Host "Shut down VM to continue? (Y/N)") -match "^[Yy]$") {
            Stop-VM -Name $vmName -Force
            do { Start-Sleep 2 } while ((Get-VM -Name $vmName).State -ne "Off")
        } else { return $false }
    }
    
    try {
        # Remove existing adapter
        Get-VMGpuPartitionAdapter -VMName $vmName -ErrorAction SilentlyContinue | Remove-VMGpuPartitionAdapter
        # Add new adapter
        Add-VMGpuPartitionAdapter -VMName $vmName
        
        # Calculate partition values
        $maxValue = [int](($percentage / 100) * 1000000000)
        $optValue = $maxValue - 1
        $minValue = 1
        
        # Configure GPU partition (all settings at once)
        Set-VMGpuPartitionAdapter -VMName $vmName `
            -MinPartitionVRAM $minValue -MaxPartitionVRAM $maxValue -OptimalPartitionVRAM $optValue `
            -MinPartitionEncode $minValue -MaxPartitionEncode $maxValue -OptimalPartitionEncode $optValue `
            -MinPartitionDecode $minValue -MaxPartitionDecode $maxValue -OptimalPartitionDecode $optValue `
            -MinPartitionCompute $minValue -MaxPartitionCompute $maxValue -OptimalPartitionCompute $optValue
        
        # Additional VM settings
        Set-VM -VMName $vmName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
        Log "GPU partition configured for '$vmName' with $percentage% allocation" "SUCCESS"
        return $true
    } catch {
        Log "GPU partition configuration failed: $_" "ERROR"
        return $false
    }
}

function Wait-ForPartitions {
    param([int]$DiskNumber, [int]$MaxRetries = 5)
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            Update-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
            $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop
            if ($partitions) { return $partitions }
        } catch {
            Start-Sleep 2
        }
    }
    return $null
}

function Remove-ExistingDrivers {
    param([string]$MountPoint)
    Log "Checking for existing NVIDIA drivers in VM..."
    
    $driverRepoPath = "$MountPoint\Windows\System32\HostDriverStore\FileRepository"
    $system32Path = "$MountPoint\Windows\System32"
    $removedItems = 0
    
    # Remove existing driver repositories
    if (Test-Path $driverRepoPath) {
        $existingDrivers = Get-ChildItem $driverRepoPath -Directory | Where-Object { $_.Name -like "nv_dispi.inf_amd64*" }
        if ($existingDrivers) {
            Log "Found $($existingDrivers.Count) existing driver repositories in VM" "WARN"
            foreach ($driver in $existingDrivers) {
                try {
                    Remove-Item $driver.FullName -Recurse -Force
                    $removedItems++
                    Log "Removed existing driver repository: $($driver.Name)" "INFO"
                } catch {
                    Log "Failed to remove driver repository: $($driver.Name) - $_" "WARN"
                }
            }
        }
    }
    
    # Remove existing NVIDIA system files
    if (Test-Path $system32Path) {
        $existingNvFiles = Get-ChildItem $system32Path -File | Where-Object { $_.Name -like "nv*" }
        if ($existingNvFiles) {
            Log "Found $($existingNvFiles.Count) existing NVIDIA system files in VM" "WARN"
            foreach ($file in $existingNvFiles) {
                try {
                    Remove-Item $file.FullName -Force
                    $removedItems++
                    Log "Removed existing NVIDIA file: $($file.Name)" "INFO"
                } catch {
                    Log "Failed to remove NVIDIA file: $($file.Name) - $_" "WARN"
                }
            }
        }
    }
    
    if ($removedItems -gt 0) {
        Log "Removed $removedItems existing NVIDIA driver components from VM" "SUCCESS"
    } else {
        Log "No existing NVIDIA drivers found in VM" "INFO"
    }
    
    return $removedItems
}

function Get-HostDriverRepositories {
    Log "Scanning for NVIDIA driver repositories on host..."
    
    $hostDriverRepos = Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "nv_dispi.inf_amd64*" } | Sort-Object Name
    
    if (!$hostDriverRepos -or $hostDriverRepos.Count -eq 0) {
        Log "No NVIDIA driver repositories found on host" "ERROR"
        return $null
    }
    
    Log "Found $($hostDriverRepos.Count) NVIDIA driver repositories on host - copying all for safety:" "INFO"
    for ($i = 0; $i -lt $hostDriverRepos.Count; $i++) {
        try {
            $sizeBytes = ($hostDriverRepos[$i] | Get-ChildItem -Recurse -File | Measure-Object Length -Sum).Sum
            $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
            Log "  [$($i + 1)] $($hostDriverRepos[$i].Name) ($sizeMB MB)" "INFO"
        } catch {
            Log "  [$($i + 1)] $($hostDriverRepos[$i].Name) (Size calculation failed)" "INFO"
        }
    }
    
    return $hostDriverRepos
}

function Add-GPUDrivers {
    param([string]$InputVMName = $null)
    Log "=== GPU DRIVER INJECTION MODULE ===" "INFO"
    
    # Ensure we have a clean string for the VM name
    $vmName = if ($InputVMName) {
        $InputVMName.ToString()
    } else {
        Read-Host "Enter the name of the VM"
    }
    
    if ([string]::IsNullOrWhiteSpace($vmName)) {
        Log "No VM name provided" "ERROR"
        return $false
    }
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (!$vm) { Log "VM '$vmName' not found" "ERROR"; return $false }
    
    $vmDisk = Get-VMHardDiskDrive -VMName $vmName
    if (!$vmDisk) { Log "No virtual hard disk found" "ERROR"; return $false }
    
    # Ensure VM is off
    if ($vm.State -ne "Off") {
        Log "VM must be powered off" "WARN"
        Read-Host "Press Enter when VM is off"
        if ((Get-VM -Name $vmName).State -ne "Off") { return $false }
    }
    
    # Get host driver repositories first (before mounting VM disk)
    $hostDriverRepos = Get-HostDriverRepositories
    if (!$hostDriverRepos) {
        Log "Cannot proceed without host NVIDIA drivers" "ERROR"
        return $false
    }
    
    # Get host NVIDIA system files
    $hostNvFiles = Get-ChildItem "C:\Windows\System32" -File | Where-Object { $_.Name -like "nv*" }
    if (!$hostNvFiles -or $hostNvFiles.Count -eq 0) {
        Log "No NVIDIA system files found on host" "ERROR"
        return $false
    }
    Log "Found $($hostNvFiles.Count) NVIDIA system files on host" "INFO"
    
    $mountPoint = "C:\Temp\VMDiskMount"
    $mountedDisk = $null
    $largestPartition = $null
    
    try {
        # Mount VHD
        $mountedDisk = Mount-VHD -Path $vmDisk.Path -NoDriveLetter -PassThru
        Start-Sleep 3
        
        # Get partitions with retry logic
        $partitions = Wait-ForPartitions -DiskNumber $mountedDisk.DiskNumber
        if (!$partitions) {
            Log "No partitions found - OS may not be installed yet" "ERROR"
            return $false
        }
        
        # Find largest suitable partition
        $largestPartition = $partitions | Where-Object { $_.Type -eq "Basic" -or $_.Size -gt 1GB } |
            Sort-Object Size -Descending | Select-Object -First 1
        if (!$largestPartition) { Log "No suitable partition found" "ERROR"; return $false }
        
        # Create mount point and map partition
        if (!(Test-Path $mountPoint)) { New-Item -Path $mountPoint -ItemType Directory -Force | Out-Null }
        Add-PartitionAccessPath -DiskNumber $mountedDisk.DiskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint
        
        # Check for Windows directory
        if (!(Test-Path "$mountPoint\Windows")) {
            if ((Read-Host "Windows directory not found. Continue anyway? (Y/N)") -notmatch "^[Yy]$") {
                return $false
            }
        }
        
        # Remove existing drivers from VM
        $removedCount = Remove-ExistingDrivers -MountPoint $mountPoint
        
        # Copy all driver repositories
        $destDriverPath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
        if (!(Test-Path $destDriverPath)) { New-Item -Path $destDriverPath -ItemType Directory -Force | Out-Null }
        
        $copiedRepos = 0
        foreach ($repo in $hostDriverRepos) {
            try {
                Copy-Item -Path $repo.FullName -Destination $destDriverPath -Recurse -Force
                $copiedRepos++
                Log "Copied driver repository: $($repo.Name)" "INFO"
            } catch {
                Log "Failed to copy driver repository: $($repo.Name) - $_" "ERROR"
            }
        }
        
        # Copy all NVIDIA system files
        $destSystem32 = "$mountPoint\Windows\System32"
        $copiedFiles = 0
        foreach ($file in $hostNvFiles) {
            try {
                Copy-Item -Path $file.FullName -Destination $destSystem32 -Force
                $copiedFiles++
            } catch {
                Log "Failed to copy system file: $($file.Name)" "WARN"
            }
        }
        
        Log "Driver injection completed - Repositories: $copiedRepos, System Files: $copiedFiles, Removed Old: $removedCount" "SUCCESS"
        return $true
    } catch {
        Log "Driver injection failed: $_" "ERROR"
        return $false
    } finally {
        # Cleanup
        if ($mountedDisk -and $largestPartition) {
            try { Remove-PartitionAccessPath -DiskNumber $mountedDisk.DiskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint -ErrorAction SilentlyContinue } catch { }
        }
        if ($vmDisk) {
            try { Dismount-VHD -Path $vmDisk.Path -ErrorAction SilentlyContinue } catch { }
        }
        if (Test-Path $mountPoint) {
            try { Remove-Item -Path $mountPoint -Force -Recurse -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function Update-GPUDriversOverwritten {
    Log "=== GPU DRIVER UPDATE MODULE ===" "INFO"
    Log "This will remove old GPU drivers and install the latest version from the host" "WARN"
    
    # Confirm the user wants to proceed with driver update
    if ((Read-Host "Continue with driver update? (Y/N)") -notmatch "^[Yy]$") {
        Log "Driver update cancelled by user" "INFO"
        return $false
    }
    
    # This calls Add-GPUDrivers which now handles proper cleanup and replacement
    if (Add-GPUDrivers) {
        Log "GPU drivers updated successfully - VM drivers now match host version" "SUCCESS"
        return $true
    } else {
        Log "GPU driver update failed" "ERROR"
        return $false
    }
}

function Complete-GPUSetup {
    Log "=== COMPLETE GPU SETUP MODULE ===" "INFO"
    $vmName = Create-VM
    if ([string]::IsNullOrWhiteSpace($vmName)) {
        Log "VM creation failed" "ERROR"
        return
    }
    
    # Ensure we pass just the VM name string
    Log "VM creation successful. Proceeding with GPU partition creation..." "SUCCESS"
    if (!(Create-GPUPartition -InputVMName $vmName)) {
        Log "GPU partition failed" "ERROR"
        return
    }
    Log "VM '$vmName' created with GPU partition. Install OS first, then run option 3 for drivers." "SUCCESS"
}

# Main execution
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$continueLoop = $true
while ($continueLoop) {
    Show-Menu
    $choice = Read-Host "Select an option (1-6)"
    switch ($choice) {
        "1" {
            $vmName = Create-VM
            if ($vmName) { Log "VM '$vmName' created successfully" "SUCCESS" }
            Read-Host "Press Enter to continue"
        }
        "2" {
            if (Create-GPUPartition) { Log "GPU partition created successfully" "SUCCESS" }
            Read-Host "Press Enter to continue"
        }
        "3" {
            if (Add-GPUDrivers) { Log "GPU drivers injected successfully" "SUCCESS" }
            Read-Host "Press Enter to continue"
        }
        "4" {
            Complete-GPUSetup
            Read-Host "Press Enter to continue"
        }
        "5" {
            if (Update-GPUDriversOverwritten) { Log "GPU drivers updated successfully" "SUCCESS" }
            Read-Host "Press Enter to continue"
        }
        "6" {
            Log "Exiting VM Manager..." "INFO"
            $continueLoop = $false
        }
        default {
            Log "Invalid selection" "WARN"
            Start-Sleep 1
        }
    }
}

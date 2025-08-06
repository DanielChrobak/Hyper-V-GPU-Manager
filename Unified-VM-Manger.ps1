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
        $tmpEnabled = Setup-VMTPM -VMName $config.Name
        
        # Attach ISO if exists
        $isoAttached = $false
        if (Test-Path $config.ISO) {
            Add-VMDvdDrive -VMName $config.Name -Path $config.ISO
            $isoAttached = $true
        }
        Log "VM '$($config.Name)' created successfully - RAM: $($config.RAM)GB, CPU: $($config.CPU), TPM: $tmpEnabled, ISO: $isoAttached" "SUCCESS"
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
        
        # Find and copy NVIDIA drivers
        $nvDriverRepo = Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory |
            Where-Object { $_.Name -like "nv_dispi.inf_amd64*" } | Select-Object -First 1
        if (!$nvDriverRepo) { Log "NVIDIA drivers not found on host" "ERROR"; return $false }
        
        # Copy driver repository
        $destDriverPath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
        if (!(Test-Path $destDriverPath)) { New-Item -Path $destDriverPath -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $nvDriverRepo.FullName -Destination $destDriverPath -Recurse -Force
        
        # Copy NVIDIA system files
        $nvFiles = Get-ChildItem "C:\Windows\System32" -File | Where-Object { $_.Name -like "nv*" }
        $destSystem32 = "$mountPoint\Windows\System32"
        $copiedCount = 0
        foreach ($file in $nvFiles) {
            try {
                Copy-Item -Path $file.FullName -Destination $destSystem32 -Force
                $copiedCount++
            } catch { }
        }
        Log "Driver injection completed - Repository: $($nvDriverRepo.Name), Files: $copiedCount" "SUCCESS"
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
    Log "This will overwrite existing GPU drivers with the latest version from the host" "WARN"
    
    # Confirm the user wants to proceed with driver update
    if ((Read-Host "Continue with driver update? (Y/N)") -notmatch "^[Yy]$") {
        Log "Driver update cancelled by user" "INFO"
        return $false
    }
    
    # This calls Add-GPUDrivers to overwrite drivers in the VM
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

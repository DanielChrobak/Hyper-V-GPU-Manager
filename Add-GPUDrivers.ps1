# Add-GPUDrivers.ps1 (Shortened)
function Log {
    param ([string]$M, [string]$T = "INFO")
    Write-Host "[$T] $M"
}

# Check admin rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Log "Requesting admin rights..." "WARN"
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Get VM disk
try {
    Log "Getting TestVM disk info..."
    $vmDisk = Get-VMHardDiskDrive -VMName "TestVM"
    if (!$vmDisk) {
        Log "No disk found for TestVM" "ERROR"
        exit
    }
    Log "VM disk path: $($vmDisk.Path)"
} catch {
    Log "Error getting disk info: $_" "ERROR"
    exit
}

# Check VM state
try {
    $vmState = (Get-VM -Name "TestVM").State
    while ($vmState -ne "Off") {
        Log "VM is $vmState. Please shut it off." "WARN"
        Read-Host "Press Enter when VM is off"
        $vmState = (Get-VM -Name "TestVM").State
    }
    Log "VM is off. Proceeding."
} catch {
    Log "Error checking VM state: $_" "ERROR"
    exit
}

# Mount VHD
$mountPoint = "C:\Temp\VMDiskMount"
try {
    Log "Mounting VHD..."
    $mountedDisk = Mount-VHD -Path $vmDisk.Path -NoDriveLetter -PassThru
    
    # Get largest partition
    $diskNumber = $mountedDisk.DiskNumber
    $largestPartition = Get-Partition -DiskNumber $diskNumber | 
                        Where-Object { $_.Type -eq "Basic" } | 
                        Sort-Object -Property Size -Descending | 
                        Select-Object -First 1
    
    # Create mount point
    if (!(Test-Path $mountPoint)) {
        New-Item -Path $mountPoint -ItemType Directory -Force | Out-Null
    }
    
    # Add access path
    Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint
    
    # Find NVIDIA driver repo
    $nvDriverRepo = Get-ChildItem -Path "C:\Windows\System32\DriverStore\FileRepository" -Directory | 
                    Where-Object { $_.Name -like "nv_dispi.inf_amd64*" } | 
                    Select-Object -First 1
    
    if ($nvDriverRepo) {
        Log "Found NVIDIA repo: $($nvDriverRepo.Name)"
        
        # Create destination directory
        $destDriverPath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
        if (!(Test-Path $destDriverPath)) {
            New-Item -Path $destDriverPath -ItemType Directory -Force | Out-Null
        }
        
        # Copy driver repo
        Copy-Item -Path $nvDriverRepo.FullName -Destination $destDriverPath -Recurse -Force
        
        # Copy nv* files
        $nvFiles = Get-ChildItem -Path "C:\Windows\System32" -File | Where-Object { $_.Name -like "nv*" }
        $destSystem32Path = "$mountPoint\Windows\System32"
        
        $copiedCount = 0
        foreach ($file in $nvFiles) {
            try {
                Copy-Item -Path $file.FullName -Destination $destSystem32Path -Force
                $copiedCount++
            } catch { }
        }
        Log "$copiedCount nv* files copied"
    } else {
        Log "NVIDIA driver repo not found" "ERROR"
    }
} catch {
    Log "Error: $_" "ERROR"
} finally {
    # Cleanup
    if ($diskNumber -and $largestPartition) {
        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint -ErrorAction SilentlyContinue
    }
    
    if ($vmDisk) {
        Dismount-VHD -Path $vmDisk.Path -ErrorAction SilentlyContinue
        Log "VHD dismounted"
    }
    
    if (Test-Path $mountPoint) {
        Remove-Item -Path $mountPoint -Force -Recurse -ErrorAction SilentlyContinue
    }
}

Log "GPU driver injection completed. Start VM and install drivers."
Read-Host "Press Enter to exit"

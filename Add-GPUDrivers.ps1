# Add-GPUDrivers.ps1 (Enhanced Logging)
function Log {
    param ([string]$M, [string]$T = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp][$T] $M"
}

# Check admin rights
Log "Verifying administrative privileges"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Log "Script requires elevation. Requesting admin rights..." "WARN"
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Log "Administrative privileges confirmed" "SUCCESS"

# Get VM name from user input
Log "Prompting for target VM name"
$vmName = Read-Host "Enter the name of the VM"
if ([string]::IsNullOrWhiteSpace($vmName)) {
    Log "No VM name provided. Cannot proceed with driver injection." "ERROR"
    exit
}
Log "Target VM: $vmName" "INFO"

# Get VM disk
try {
    Log "Retrieving virtual disk information for VM '$vmName'"
    $vm = Get-VM -Name $vmName -ErrorAction Stop
    if (!$vm) {
        Log "VM '$vmName' not found in Hyper-V" "ERROR"
        exit
    }
    Log "VM found: $vmName (Generation: $($vm.Generation), State: $($vm.State))" "SUCCESS"
    
    $vmDisk = Get-VMHardDiskDrive -VMName $vmName
    if (!$vmDisk) {
        Log "No virtual hard disk attached to VM '$vmName'" "ERROR"
        exit
    }
    Log "VM disk identified: $($vmDisk.Path)" "SUCCESS"
    Log "Disk controller: $($vmDisk.ControllerType) $($vmDisk.ControllerNumber):$($vmDisk.ControllerLocation)" "INFO"
} catch {
    Log "Failed to retrieve VM disk information: $_" "ERROR"
    Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit
}

# Check VM state
try {
    Log "Verifying VM power state"
    $vmState = $vm.State
    if ($vmState -ne "Off") {
        Log "VM is currently in '$vmState' state" "WARN"
        Log "VM must be powered off before proceeding with driver injection" "WARN"
        
        $shutdownAttempt = 0
        while ($vmState -ne "Off" -and $shutdownAttempt -lt 3) {
            $shutdownAttempt++
            Log "Waiting for VM shutdown (attempt $shutdownAttempt of 3)..." "WARN"
            Read-Host "Press Enter when VM is off"
            $vmState = (Get-VM -Name $vmName).State
        }
        
        if ($vmState -ne "Off") {
            Log "VM is still not powered off after multiple attempts. Cannot proceed." "ERROR"
            exit
        }
    }
    Log "VM is powered off. Ready to proceed with driver injection." "SUCCESS"
} catch {
    Log "Error checking VM power state: $_" "ERROR"
    Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit
}

# Mount VHD
$mountPoint = "C:\Temp\VMDiskMount"
Log "Mount point will be: $mountPoint"

try {
    Log "Initiating VHD mount process"
    Log "Mounting VHD file: $($vmDisk.Path)"
    $mountedDisk = Mount-VHD -Path $vmDisk.Path -NoDriveLetter -PassThru
    Log "VHD mounted successfully with disk number: $($mountedDisk.DiskNumber)" "SUCCESS"
    
    # Get largest partition
    $diskNumber = $mountedDisk.DiskNumber
    Log "Identifying main OS partition on disk $diskNumber"
    $partitions = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -eq "Basic" }
    Log "Found $($partitions.Count) basic partitions on disk" "INFO"
    
    $largestPartition = $partitions | Sort-Object -Property Size -Descending | Select-Object -First 1
    Log "Selected partition #$($largestPartition.PartitionNumber) (Size: $([math]::Round($largestPartition.Size/1GB, 2)) GB)" "SUCCESS"
    
    # Create mount point
    if (!(Test-Path $mountPoint)) {
        Log "Creating mount point directory: $mountPoint"
        New-Item -Path $mountPoint -ItemType Directory -Force | Out-Null
        Log "Mount point directory created" "SUCCESS"
    } else {
        Log "Mount point directory already exists" "INFO"
    }
    
    # Add access path
    Log "Mapping partition to mount point"
    Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint
    Log "Partition successfully mapped to $mountPoint" "SUCCESS"
    
    # Find NVIDIA driver repo
    Log "Searching for NVIDIA driver repository on host system"
    $driverStorePath = "C:\Windows\System32\DriverStore\FileRepository"
    Log "Scanning: $driverStorePath"
    
    $nvDriverRepo = Get-ChildItem -Path $driverStorePath -Directory | 
                    Where-Object { $_.Name -like "nv_dispi.inf_amd64*" } | 
                    Select-Object -First 1
    
    if ($nvDriverRepo) {
        Log "Found NVIDIA driver repository: $($nvDriverRepo.Name)" "SUCCESS"
        Log "Full path: $($nvDriverRepo.FullName)" "INFO"
        
        # Create destination directory
        $destDriverPath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
        Log "Creating destination directory: $destDriverPath"
        if (!(Test-Path $destDriverPath)) {
            New-Item -Path $destDriverPath -ItemType Directory -Force | Out-Null
            Log "Destination directory created" "SUCCESS"
        }
        
        # Copy driver repo
        Log "Copying NVIDIA driver repository to VM disk"
        Log "Source: $($nvDriverRepo.FullName)"
        Log "Destination: $destDriverPath\$($nvDriverRepo.Name)"
        Copy-Item -Path $nvDriverRepo.FullName -Destination $destDriverPath -Recurse -Force
        Log "Driver repository copied successfully" "SUCCESS"
        
        # Copy nv* files
        Log "Searching for NVIDIA system files in C:\Windows\System32"
        $nvFiles = Get-ChildItem -Path "C:\Windows\System32" -File | Where-Object { $_.Name -like "nv*" }
        Log "Found $($nvFiles.Count) NVIDIA-related files" "INFO"
        
        $destSystem32Path = "$mountPoint\Windows\System32"
        Log "Target directory for system files: $destSystem32Path"
        
        $copiedCount = 0
        $failedCount = 0
        foreach ($file in $nvFiles) {
            try {
                Copy-Item -Path $file.FullName -Destination $destSystem32Path -Force
                $copiedCount++
                if ($copiedCount % 20 -eq 0) {
                    Log "Copied $copiedCount of $($nvFiles.Count) files..." "INFO"
                }
            } catch {
                $failedCount++
                Log "Failed to copy $($file.Name): $_" "DEBUG"
            }
        }
        Log "System file copy completed: $copiedCount files copied, $failedCount files failed" "SUCCESS"
    } else {
        Log "NVIDIA driver repository not found on host system" "ERROR"
        Log "Please ensure NVIDIA drivers are installed on the host system" "WARN"
    }
} catch {
    Log "Error during driver injection process: $_" "ERROR"
    Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
} finally {
    # Cleanup
    Log "Starting cleanup process"
    
    if ($diskNumber -and $largestPartition) {
        Log "Removing partition access path"
        try {
            Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint -ErrorAction SilentlyContinue
            Log "Partition access path removed" "SUCCESS"
        } catch {
            Log "Failed to remove partition access path: $_" "WARN"
        }
    }
    
    if ($vmDisk) {
        Log "Dismounting VHD"
        try {
            Dismount-VHD -Path $vmDisk.Path -ErrorAction SilentlyContinue
            Log "VHD dismounted successfully" "SUCCESS"
        } catch {
            Log "Failed to dismount VHD: $_" "WARN"
        }
    }
    
    if (Test-Path $mountPoint) {
        Log "Removing mount point directory"
        try {
            Remove-Item -Path $mountPoint -Force -Recurse -ErrorAction SilentlyContinue
            Log "Mount point directory removed" "SUCCESS"
        } catch {
            Log "Failed to remove mount point directory: $_" "WARN"
        }
    }
    
    Log "Cleanup process completed" "INFO"
}

Log "GPU driver injection process completed" "SUCCESS"
Log "The VM should now have access to the host's NVIDIA drivers" "INFO"
Read-Host "Press Enter to exit"

# Hyper-V-GPU-Partitioning.ps1
# Complete GPU Partitioning Solution for Hyper-V VMs
# Combines VM creation, GPU driver injection, and GPU partitioning in one script

#region Setup and functions
# Enable advanced functionality
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Setup logging
function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO"
    )

    $colors = @{
        "INFO" = "White"
        "WARN" = "Yellow"
        "ERROR" = "Red"
        "SUCCESS" = "Green"
    }

    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timeStamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

# Function to pause and prompt user
function Pause-WithPrompt {
    param ([string]$Message = "Press Enter to continue...")

    Write-Host $Message -ForegroundColor Cyan
    [void][System.Console]::ReadKey($true)
}

# Function to prompt user with Yes/No question and confirmation
function Confirm-UserChoice {
    param (
        [Parameter(Mandatory=$true)][string]$Question,
        [string]$ConfirmationPrompt = "Are you sure? (Y/N)",
        [switch]$NoConfirmation
    )

    do {
        $response = Read-Host "$Question (Y/N)"
        if ($response -notmatch "^[YyNn]$") {
            Write-Log "Please enter Y or N" "WARN"
            continue
        }

        if ($NoConfirmation -or $response -match "^[Nn]$") {
            return $response -match "^[Yy]$"
        }

        $confirm = Read-Host $ConfirmationPrompt
        if ($confirm -match "^[Yy]$") {
            return $response -match "^[Yy]$"
        }
    } while ($true)
}

# Function to enable TPM on a VM
function Enable-VMTPMFeatures {
    param([Parameter(Mandatory=$true)][string]$VMName)

    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            Write-Log "Virtual Machine '$VMName' does not exist." "ERROR"
            return $false
        }

        if ($vm.Generation -ne 2) {
            Write-Log "VM '$VMName' is not a Generation 2 VM. TPM can only be enabled on Generation 2 VMs." "ERROR"
            return $false
        }

        # Turn off VM if running
        if ($vm.State -ne "Off") {
            Write-Log "VM '$VMName' needs to be turned off to enable TPM. Shutting down now..." "WARN"
            Stop-VM -Name $VMName -Force

            # Wait for VM to be off (max 30 seconds)
            $timeout = 30
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ((Get-VM -Name $VMName).State -ne "Off" -and $timer.Elapsed.TotalSeconds -lt $timeout) {
                Start-Sleep -Seconds 2
            }

            if ((Get-VM -Name $VMName).State -ne "Off") {
                Write-Log "Failed to shut down VM '$VMName' within the timeout period." "ERROR"
                return $false
            }
        }

        # Enable TPM
        Write-Log "Enabling TPM for VM '$VMName'..."
        Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
        Enable-VMTPM -VMName $VMName

        # Verify TPM is enabled
        $tpmEnabled = (Get-VMSecurity -VMName $VMName).TpmEnabled
        if (!$tpmEnabled) {
            Write-Log "Failed to enable TPM for VM '$VMName'" "ERROR"
        }

        return $tpmEnabled
    } catch {
        Write-Log "An error occurred while enabling TPM: $_" "ERROR"
        return $false
    }
}

# Function to check if a VM exists
function Test-VMExists {
    param([Parameter(Mandatory=$true)][string]$VMName)

    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    return ($null -ne $vm)
}

# Function to ensure VM is off
function Ensure-VMIsOff {
    param([Parameter(Mandatory=$true)][string]$VMName)

    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($null -eq $vm) {
        Write-Log "VM '$VMName' does not exist." "ERROR"
        return $false
    }

    if ($vm.State -eq "Off") {
        return $true
    }

    Write-Log "VM '$VMName' is currently $($vm.State)." "WARN"
    if (Confirm-UserChoice -Question "Do you want to shut down the VM?") {
        Write-Log "Shutting down VM '$VMName'..." "WARN"
        Stop-VM -Name $VMName -Force

        # Wait for VM to be off (max 30 seconds)
        $timeout = 30
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ((Get-VM -Name $VMName).State -ne "Off" -and $timer.Elapsed.TotalSeconds -lt $timeout) {
            Start-Sleep -Seconds 2
        }

        if ((Get-VM -Name $VMName).State -eq "Off") {
            Write-Log "VM '$VMName' shut down successfully." "SUCCESS"
            return $true
        } else {
            Write-Log "Failed to shut down VM '$VMName' within the timeout period." "ERROR"
            return $false
        }
    }

    return $false
}
#endregion

#region Main script

# Elevate to administrator if needed
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "Requesting administrator privileges..." "WARN"
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Script variables
$script:VMName = $null
$script:State = "INIT"
$script:VMConfig = @{
    RAMSizeGB = 8
    CPUCount = 4
    StorageSizeGB = 128
    VHDPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
    ISOPath = $null
}
$script:GPUConfig = @{
    Percentage = 50
}

# Show banner
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "   HYPER-V GPU PARTITIONING TOOLKIT" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan
Write-Host "This script will guide you through the process of:" -ForegroundColor White
Write-Host " 1. Creating a Generation 2 VM with TPM enabled" -ForegroundColor White
Write-Host " 2. Installing the OS and configuring the VM" -ForegroundColor White
Write-Host " 3. Injecting GPU drivers into the VM" -ForegroundColor White
Write-Host " 4. Configuring GPU partitioning" -ForegroundColor White
Write-Host "`nLet's get started!`n" -ForegroundColor White

# Main workflow
try {
    #region VM Creation
    if ($script:State -eq "INIT") {
        Write-Host "`n[STEP 1] CREATE VIRTUAL MACHINE" -ForegroundColor Cyan

        # Get VM configuration from user
        $script:VMName = Read-Host "Enter the name for your new VM"

        # Check if VM already exists
        if (Test-VMExists -VMName $script:VMName) {
            Write-Log "A VM with the name '$script:VMName' already exists." "WARN"
            if (Confirm-UserChoice -Question "Do you want to use the existing VM and skip to GPU driver injection?") {
                $script:State = "DRIVER_INJECTION"
            } else {
                Write-Log "Operation canceled by user." "INFO"
                exit
            }
        } else {
            $script:VMConfig.RAMSizeGB = Read-Host "Enter RAM size in GB (recommended: 8)"
            $script:VMConfig.CPUCount = Read-Host "Enter number of CPU cores (recommended: 4)"
            $script:VMConfig.StorageSizeGB = Read-Host "Enter storage size in GB (recommended: 128)"
            $customPath = Read-Host "Enter VHD storage path (press Enter for default: $($script:VMConfig.VHDPath))"
            if ($customPath) { $script:VMConfig.VHDPath = $customPath }
            $script:VMConfig.ISOPath = Read-Host "Enter full path to OS installation ISO"

            # Create the VM
            Write-Log "Creating VM '$script:VMName'..." "INFO"

            # Setup paths and sizes
            $ramBytes = [int64]$script:VMConfig.RAMSizeGB * 1GB
            $storageBytes = [int64]$script:VMConfig.StorageSizeGB * 1GB
            $vmPath = $script:VMConfig.VHDPath
            $vhdPath = Join-Path -Path $vmPath -ChildPath "$script:VMName.vhdx"

            # Check if the VHDX file already exists
            if (Test-Path -Path $vhdPath) {
                if (Confirm-UserChoice -Question "A virtual hard disk already exists at '$vhdPath'. Delete and continue?") {
                    Remove-Item -Path $vhdPath -Force
                    Write-Log "Existing VHDX deleted." "INFO"
                } else {
                    Write-Log "Operation canceled by user." "INFO"
                    exit
                }
            }

            # Create directories if needed
            if (!(Test-Path -Path $vmPath)) {
                New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
                Write-Log "Created directory: $vmPath" "INFO"
            }

            # Create and configure the VM
            New-VM -Name $script:VMName -MemoryStartupBytes $ramBytes -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes $storageBytes
            Set-VMProcessor -VMName $script:VMName -Count $script:VMConfig.CPUCount
            Set-VMMemory -VMName $script:VMName -DynamicMemoryEnabled $false -StartupBytes $ramBytes
            Set-VM -Name $script:VMName -CheckpointType Disabled

            # Disable Enhanced Session Mode
            Write-Log "Disabling Enhanced Session Mode..."
            Set-VMHost -EnableEnhancedSessionMode $false

            # Disable Guest Service Interface
            Write-Log "Disabling Guest Service Interface..."
            Disable-VMIntegrationService -VMName $script:VMName -Name "Guest Service Interface"

            # Enable TPM for Windows 11 compatibility
            $tpmEnabled = Enable-VMTPMFeatures -VMName $script:VMName

            # Attach ISO if path is valid
            if (Test-Path -Path $script:VMConfig.ISOPath) {
                Add-VMDvdDrive -VMName $script:VMName -Path $script:VMConfig.ISOPath
                Write-Log "ISO attached successfully." "INFO"
            } else {
                Write-Log "ISO path '$($script:VMConfig.ISOPath)' is invalid. Please attach an ISO manually." "WARN"
            }

            # Display summary
            Write-Host "`n--- VM CONFIGURATION SUMMARY ---" -ForegroundColor Green
            Write-Host "VM Name: $script:VMName" -ForegroundColor White
            Write-Host "CPU Cores: $($script:VMConfig.CPUCount)" -ForegroundColor White
            Write-Host "RAM: $($script:VMConfig.RAMSizeGB) GB" -ForegroundColor White
            Write-Host "Storage: $($script:VMConfig.StorageSizeGB) GB" -ForegroundColor White
            Write-Host "VHD Path: $vhdPath" -ForegroundColor White
            Write-Host "Checkpoints: Disabled" -ForegroundColor White
            Write-Host "Enhanced Session Mode: Disabled" -ForegroundColor White
            Write-Host "Guest Service Interface: Disabled" -ForegroundColor White
            Write-Host "TPM Enabled: $(if ($tpmEnabled) { 'Yes' } else { 'No' })" -ForegroundColor White
            Write-Host "ISO Attached: $(if (Test-Path -Path $script:VMConfig.ISOPath) { 'Yes' } else { 'No' })" -ForegroundColor White
            Write-Host "--------------------------------`n" -ForegroundColor Green

            Write-Host "`n[NEXT STEPS]" -ForegroundColor Cyan
            Write-Host "1. Install the operating system on the VM." -ForegroundColor White
            Write-Host "2. Complete the OS setup process." -ForegroundColor White
            Write-Host "3. Once at the desktop, return to this script." -ForegroundColor White

            if (Confirm-UserChoice -Question "Is the OS installed and VM booted to the desktop?") {
                Write-Log "OS installation confirmed by user." "INFO"
                Write-Log "Proceeding to driver injection phase." "INFO"

                # Shutdown VM for driver injection
                if (Ensure-VMIsOff -VMName $script:VMName) {
                    $script:State = "DRIVER_INJECTION"
                } else {
                    Write-Log "VM must be off to continue. Please shut down the VM and run the script again." "ERROR"
                    exit
                }
            } else {
                Write-Log "Please complete OS installation before continuing." "INFO"
                Write-Log "Run this script again after OS installation is complete." "INFO"
                exit
            }
        }
    }
    #endregion

    #region Driver Injection
    if ($script:State -eq "DRIVER_INJECTION") {
        Write-Host "`n[STEP 2] GPU DRIVER INJECTION" -ForegroundColor Cyan

        # Check if VM exists
        if (-not (Test-VMExists -VMName $script:VMName)) {
            Write-Log "VM '$script:VMName' does not exist." "ERROR"
            exit
        }

        # Ensure VM is off
        if (-not (Ensure-VMIsOff -VMName $script:VMName)) {
            Write-Log "VM must be off to inject GPU drivers." "ERROR"
            exit
        }

        # Get VM disk
        try {
            Write-Log "Retrieving hard disk information..." "INFO"
            $vmDisk = Get-VMHardDiskDrive -VMName $script:VMName

            if ($vmDisk) {
                Write-Log "VM Hard Disk Path: $($vmDisk.Path)" "INFO"
            } else {
                Write-Log "No hard disk found for VM '$script:VMName'" "ERROR"
                exit
            }
        } catch {
            Write-Log "Error retrieving VM hard disk: $_" "ERROR"
            exit
        }

        # Inject GPU drivers
        try {
            Write-Log "Starting GPU driver injection process..." "INFO"
            $mountPoint = "C:\Temp\VMDiskMount"

            # Mount the VHD/VHDX
            Write-Log "Mounting virtual hard disk..." "INFO"
            $mountedDisk = Mount-VHD -Path $vmDisk.Path -NoDriveLetter -PassThru

            if ($mountedDisk) {
                # Get all partitions of the mounted disk
                $diskNumber = $mountedDisk.DiskNumber
                $partitions = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -eq "Basic" }

                if ($partitions) {
                    # Find the largest partition (typically the OS partition)
                    $largestPartition = $partitions | Sort-Object -Property Size -Descending | Select-Object -First 1
                    Write-Log "Found OS partition (Size: $([math]::Round($largestPartition.Size/1GB, 2)) GB)" "INFO"

                    # Create a temporary mount point
                    if (-not (Test-Path -Path $mountPoint)) {
                        New-Item -Path $mountPoint -ItemType Directory -Force | Out-Null
                    }

                    # Add access path to the partition
                    Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint

                    # Find NVIDIA driver repository folder
                    Write-Log "Searching for NVIDIA driver repository..." "INFO"
                    $nvDriverRepo = Get-ChildItem -Path "C:\Windows\System32\DriverStore\FileRepository" -Directory |
                                   Where-Object { $_.Name -like "nv_dispi.inf_amd64*" } |
                                   Select-Object -First 1

                    if ($nvDriverRepo) {
                        Write-Log "Found NVIDIA driver repository: $($nvDriverRepo.Name)" "SUCCESS"

                        # Create destination directory
                        $destDriverPath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
                        if (-not (Test-Path -Path $destDriverPath)) {
                            New-Item -Path $destDriverPath -ItemType Directory -Force | Out-Null
                        }

                        # Copy NVIDIA driver repository folder
                        Write-Log "Copying NVIDIA driver repository to VM..." "INFO"
                        $destFolderPath = Join-Path -Path $destDriverPath -ChildPath $nvDriverRepo.Name
                        Copy-Item -Path $nvDriverRepo.FullName -Destination $destFolderPath -Recurse -Force

                        # Copy all nv* files from System32
                        Write-Log "Copying NVIDIA system files..." "INFO"
                        $nvFiles = Get-ChildItem -Path "C:\Windows\System32" -File | Where-Object { $_.Name -like "nv*" }
                        $destSystem32Path = "$mountPoint\Windows\System32"

                        $copiedCount = 0
                        foreach ($file in $nvFiles) {
                            try {
                                Copy-Item -Path $file.FullName -Destination $destSystem32Path -Force
                                $copiedCount++
                            } catch {
                                Write-Log "Failed to copy $($file.Name): $_" "ERROR"
                            }
                        }

                        Write-Log "$copiedCount NVIDIA files copied successfully" "SUCCESS"
                    } else {
                        Write-Log "NVIDIA driver repository not found. Is the NVIDIA GPU driver installed on the host?" "ERROR"
                    }

                    # Remove access path
                    Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $largestPartition.PartitionNumber -AccessPath $mountPoint
                } else {
                    Write-Log "No basic partitions found on the mounted disk" "ERROR"
                }
            } else {
                Write-Log "Failed to mount the virtual disk" "ERROR"
            }
        } catch {
            Write-Log "Error during driver injection: $_" "ERROR"
        } finally {
            # Dismount the VHD safely
            if ($mountedDisk) {
                Dismount-VHD -Path $vmDisk.Path
                Write-Log "Virtual disk dismounted" "INFO"
            }

            # Clean up the temporary mount point
            if (Test-Path -Path $mountPoint) {
                Remove-Item -Path $mountPoint -Force -Recurse
            }
        }

        # Start VM and guide user through driver installation
        Write-Log "GPU driver injection completed" "SUCCESS"
        Write-Host "`n[NEXT STEPS]" -ForegroundColor Cyan
        Write-Host "1. Start the VM (the script will do this for you)" -ForegroundColor White
        Write-Host "2. Install the injected GPU drivers from Device Manager" -ForegroundColor White
        Write-Host "3. Install Remote Desktop services" -ForegroundColor White
        Write-Host "4. Configure Remote Desktop settings" -ForegroundColor White

        if (Confirm-UserChoice -Question "Do you want to start the VM now?") {
            Start-VM -Name $script:VMName

            Write-Host "`n=== IMPORTANT SETUP INSTRUCTIONS ===" -ForegroundColor Yellow
            Write-Host "Follow these steps in the VM:" -ForegroundColor White
            Write-Host "1. Download and Install Remote Desktop Software (e.g., VNC like TightVNC)." -ForegroundColor White
            Write-Host "2. Download and Install VB Cable, you will need this for audio." -ForegroundColor White
            Write-Host "3. Download a Virtual Display Driver (e.g., ItsMikeTheTech VDD)." -ForegroundColor White
            Write-Host "4. Configure your Remote Desktop Software and Reboot the VM." -ForegroundColor White
            Write-Host "   Never use Hyper-V's built-in RDP to connect again. Always use your chosen Remote Desktop tool from now on." -ForegroundColor White
            Write-Host "5. Using your Remote Desktop connection, open Device Manager and Disable the Hyper-V Display Adapter." -ForegroundColor White
            Write-Host "6. Disable BitLocker in Windows Settings." -ForegroundColor White
            Write-Host "==========================================" -ForegroundColor Yellow

            if (Confirm-UserChoice -Question "Have you completed the above steps?") {
                Write-Log "User confirmed the setup instructions." "INFO"

                # Shutdown VM for GPU partitioning
                if (Ensure-VMIsOff -VMName $script:VMName) {
                    $script:State = "GPU_PARTITION"
                } else {
                    Write-Log "VM must be off to configure GPU partitioning." "ERROR"
                    exit
                }
            } else {
                Write-Log "Please complete the setup instructions before continuing." "INFO"
                Write-Log "Run this script again after completion." "INFO"
                exit
            }
        } else {
            Write-Log "Please start the VM, and follow the setup instructions manually." "INFO"
            Write-Log "Run this script again after completion." "INFO"
            exit
        }
    }
    #endregion

    #region GPU Partitioning
    if ($script:State -eq "GPU_PARTITION") {
        Write-Host "`n[STEP 3] GPU PARTITIONING CONFIGURATION" -ForegroundColor Cyan

        # Check if VM exists
        if (-not (Test-VMExists -VMName $script:VMName)) {
            Write-Log "VM '$script:VMName' does not exist." "ERROR"
            exit
        }

        # Ensure VM is off
        if (-not (Ensure-VMIsOff -VMName $script:VMName)) {
            Write-Log "VM must be off to configure GPU partitioning." "ERROR"
            exit
        }

        # Ask for GPU resource percentage
        $script:GPUConfig.Percentage = Read-Host "Enter the percentage of GPU resources to assign to the VM (1-100, recommended: 50)"
        $percentage = [int]$script:GPUConfig.Percentage

        # Validate percentage input
        if ($percentage -lt 1 -or $percentage -gt 100) {
            Write-Log "Invalid percentage. Please enter a value between 1 and 100." "ERROR"
            exit
        }

        # Calculate partition values based on percentage
        $maxPartitionValue = [int](($percentage / 100) * 1000000000)
        $optimalPartitionValue = $maxPartitionValue - 1
        $minPartitionValue = 1

        Write-Log "Configuring GPU partition for VM with $percentage% resources..." "INFO"

        try {
            # Remove existing GPU partition adapter if any
            if (Get-VMGpuPartitionAdapter -VMName $script:VMName -ErrorAction SilentlyContinue) {
                Write-Log "Removing existing GPU partition adapter..." "INFO"
                Remove-VMGpuPartitionAdapter -VMName $script:VMName
            }

            # Add GPU partition adapter
            Write-Log "Adding GPU partition adapter..." "INFO"
            Add-VMGpuPartitionAdapter -VMName $script:VMName

            Write-Log "Configuring partition settings..." "INFO"

            # Configure partition settings (VRAM, Encode, Decode, Compute)
            Set-VMGpuPartitionAdapter -VMName $script:VMName -MinPartitionVRAM $minPartitionValue -MaxPartitionVRAM $maxPartitionValue -OptimalPartitionVRAM $optimalPartitionValue
            Set-VMGpuPartitionAdapter -VMName $script:VMName -MinPartitionEncode $minPartitionValue -MaxPartitionEncode $maxPartitionValue -OptimalPartitionEncode $optimalPartitionValue
            Set-VMGpuPartitionAdapter -VMName $script:VMName -MinPartitionDecode $minPartitionValue -MaxPartitionDecode $maxPartitionValue -OptimalPartitionDecode $optimalPartitionValue
            Set-VMGpuPartitionAdapter -VMName $script:VMName -MinPartitionCompute $minPartitionValue -MaxPartitionCompute $maxPartitionValue -OptimalPartitionCompute $optimalPartitionValue

            # Additional memory settings
            Write-Log "Configuring additional memory settings..." "INFO"
            Set-VM -GuestControlledCacheTypes $true -VMName $script:VMName
            Set-VM -LowMemoryMappedIoSpace 1Gb -VMName $script:VMName
            Set-VM -HighMemoryMappedIoSpace 32GB -VMName $script:VMName

            Write-Log "GPU partition configuration complete!" "SUCCESS"
            Write-Log "GPU Resources assigned: $percentage%" "SUCCESS"
        }
        catch {
            Write-Log "Error during GPU partition configuration: $_" "ERROR"
        }

        # Final success message and start VM
        Write-Host "`n=== CONFIGURATION COMPLETE! ===" -ForegroundColor Green
        Write-Host "Your VM is now configured with GPU partitioning." -ForegroundColor White
        Write-Host "Details:" -ForegroundColor White
        Write-Host "- VM Name: $script:VMName" -ForegroundColor White
        Write-Host "- GPU Resources: $percentage%" -ForegroundColor White

        if (Confirm-UserChoice -Question "Do you want to start the VM now?") {
            Start-VM -VMName $script:VMName
            Write-Log "VM '$script:VMName' started successfully." "SUCCESS"
        }
    }
    #endregion
}
catch {
    Write-Log "An unhandled error occurred: $_" "ERROR"
}
finally {
    Write-Host "`nHyper-V GPU Partitioning process completed." -ForegroundColor Cyan
    Pause-WithPrompt
}
#endregion

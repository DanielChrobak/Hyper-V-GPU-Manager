# Create-GPUPartition.ps1 (Enhanced Logging)
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

# Get VM name
Log "Prompting for target VM name"
$vmName = Read-Host "Enter VM name"
if ([string]::IsNullOrWhiteSpace($vmName)) {
    Log "No VM name provided. Cannot proceed with GPU partition creation." "ERROR"
    Read-Host "Press Enter to exit"; exit
}
Log "Target VM: $vmName" "INFO"

# Check VM exists
Log "Verifying VM exists in Hyper-V inventory"
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Log "VM '$vmName' not found in Hyper-V inventory." "ERROR"
    Read-Host "Press Enter to exit"; exit
}
Log "VM found: $vmName (Generation: $($vm.Generation), State: $($vm.State))" "SUCCESS"

# Get GPU percentage
Log "Prompting for GPU resource allocation percentage"
$percentageInput = Read-Host "Enter GPU percentage (1-100)"
if (-not [int]::TryParse($percentageInput, [ref]$null)) {
    Log "Input '$percentageInput' is not a valid integer." "ERROR"
    Read-Host "Press Enter to exit"; exit
}
$percentage = [int]$percentageInput

# Validate percentage
Log "Validating GPU percentage value: $percentage"
if ($percentage -lt 1 -or $percentage -gt 100) {
    Log "Invalid percentage value: $percentage. Must be between 1-100." "ERROR"
    Read-Host "Press Enter to exit"; exit
}
Log "GPU allocation percentage validated: $percentage%" "SUCCESS"

# Calculate values
Log "Calculating GPU partition values based on $percentage% allocation"
$maxValue = [int](($percentage / 100) * 1000000000)
$optValue = $maxValue - 1
$minValue = 1
Log "Calculated partition values:" "INFO"
Log "- Minimum: $minValue" "INFO"
Log "- Optimal: $optValue" "INFO"
Log "- Maximum: $maxValue" "INFO"

Log "Initiating GPU partition configuration for '$vmName' with $percentage% resources..."

try {
    # Check if VM is running
    if ($vm.State -eq "Running") {
        Log "VM is currently running. GPU partition changes require VM to be off." "WARN"
        $shutdownResponse = Read-Host "Shut down VM to continue? (Y/N)"
        if ($shutdownResponse -match "^[Yy]$") {
            Log "Shutting down VM '$vmName'..."
            Stop-VM -Name $vmName -Force
            
            # Wait for VM to shut down
            $timeout = 60
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ((Get-VM -Name $vmName).State -ne "Off" -and $timer.Elapsed.TotalSeconds -lt $timeout) {
                Log "Waiting for VM to shut down... ($([math]::Round($timer.Elapsed.TotalSeconds))s elapsed)" "INFO"
                Start-Sleep -s 2
            }
            
            if ((Get-VM -Name $vmName).State -ne "Off") {
                Log "VM shutdown timed out after $timeout seconds." "ERROR"
                Read-Host "Press Enter to exit"; exit
            }
            Log "VM successfully powered off after $([math]::Round($timer.Elapsed.TotalSeconds))s" "SUCCESS"
        } else {
            Log "User declined to shut down VM. Cannot proceed with GPU partition configuration." "WARN"
            Read-Host "Press Enter to exit"; exit
        }
    }

    # Remove existing GPU adapter if any
    Log "Checking for existing GPU partition adapters"
    $existingAdapter = Get-VMGpuPartitionAdapter -VMName $vmName -ErrorAction SilentlyContinue
    if ($existingAdapter) {
        Log "Found existing GPU partition adapter. Removing..." "WARN"
        Remove-VMGpuPartitionAdapter -VMName $vmName
        Log "Existing GPU partition adapter removed" "SUCCESS"
    } else {
        Log "No existing GPU partition adapter found" "INFO"
    }

    # Add GPU adapter
    Log "Adding new GPU partition adapter to VM"
    Add-VMGpuPartitionAdapter -VMName $vmName
    Log "GPU partition adapter added successfully" "SUCCESS"

    # Configure all partition settings
    Log "Configuring GPU partition settings with $percentage% allocation"
    $params = @{
        VMName = $vmName
        MinPartitionVRAM = $minValue
        MaxPartitionVRAM = $maxValue
        OptimalPartitionVRAM = $optValue
        MinPartitionEncode = $minValue
        MaxPartitionEncode = $maxValue
        OptimalPartitionEncode = $optValue
        MinPartitionDecode = $minValue
        MaxPartitionDecode = $maxValue
        OptimalPartitionDecode = $optValue
        MinPartitionCompute = $minValue
        MaxPartitionCompute = $maxValue
        OptimalPartitionCompute = $optValue
    }
    Set-VMGpuPartitionAdapter @params
    Log "GPU partition adapter settings applied" "SUCCESS"

    # Additional settings
    Log "Configuring additional memory settings for optimal GPU performance"
    Log "Enabling guest controlled cache types"
    Set-VM -GuestControlledCacheTypes $true -VMName $vmName
    
    Log "Setting low memory mapped I/O space to 1GB"
    Set-VM -LowMemoryMappedIoSpace 1Gb -VMName $vmName
    
    Log "Setting high memory mapped I/O space to 32GB"
    Set-VM -HighMemoryMappedIoSpace 32GB -VMName $vmName
    
    Log "Memory settings configured successfully" "SUCCESS"

    # Verify configuration
    Log "Verifying GPU partition configuration"
    $adapter = Get-VMGpuPartitionAdapter -VMName $vmName
    if ($adapter) {
        Log "GPU PARTITION CONFIGURATION SUMMARY:" "SUCCESS"
        Log "- VM Name: $vmName" "SUCCESS"
        Log "- Allocation: $percentage%" "SUCCESS"
        Log "- VRAM: Min=$($adapter.MinPartitionVRAM), Max=$($adapter.MaxPartitionVRAM)" "SUCCESS"
        Log "- Encode: Min=$($adapter.MinPartitionEncode), Max=$($adapter.MaxPartitionEncode)" "SUCCESS"
        Log "- Decode: Min=$($adapter.MinPartitionDecode), Max=$($adapter.MaxPartitionDecode)" "SUCCESS"
        Log "- Compute: Min=$($adapter.MinPartitionCompute), Max=$($adapter.MaxPartitionCompute)" "SUCCESS"
    } else {
        Log "Failed to retrieve GPU partition configuration for verification" "WARN"
    }
} catch {
    Log "Error during GPU partition configuration: $_" "ERROR"
    Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
}

Log "GPU partition configuration process completed" "SUCCESS"
Log "The VM '$vmName' has been configured with $percentage% GPU resources" "INFO"
Log "You may now start the VM and utilize the GPU resources" "INFO"
Read-Host "Press Enter to exit"

# Create-GPUPartition.ps1 (Shortened)
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

# Get VM name
$vmName = Read-Host "Enter VM name"

# Check VM exists
if (-not (Get-VM -Name $vmName -ErrorAction SilentlyContinue)) {
    Log "VM '$vmName' not found." "ERROR"
    Read-Host "Press Enter to exit"; exit
}

# Get GPU percentage
$percentage = [int](Read-Host "Enter GPU percentage (1-100)")

# Validate percentage
if ($percentage -lt 1 -or $percentage -gt 100) {
    Log "Invalid percentage. Must be 1-100." "ERROR"
    Read-Host "Press Enter to exit"; exit
}

# Calculate values
$maxValue = [int](($percentage / 100) * 1000000000)
$optValue = $maxValue - 1
$minValue = 1

Log "Configuring GPU partition for '$vmName' with $percentage% resources..."

try {
    # Remove existing GPU adapter if any
    if (Get-VMGpuPartitionAdapter -VMName $vmName -ErrorAction SilentlyContinue) {
        Log "Removing existing GPU adapter..."
        Remove-VMGpuPartitionAdapter -VMName $vmName
    }

    # Add GPU adapter
    Log "Adding GPU adapter..."
    Add-VMGpuPartitionAdapter -VMName $vmName

    # Configure all partition settings
    Log "Setting partition values..."
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

    # Additional settings
    Log "Configuring memory settings..."
    Set-VM -GuestControlledCacheTypes $true -VMName $vmName
    Set-VM -LowMemoryMappedIoSpace 1Gb -VMName $vmName
    Set-VM -HighMemoryMappedIoSpace 32GB -VMName $vmName

    Log "GPU partition configured: $percentage% resources" "SUCCESS"
} catch {
    Log "Error: $_" "ERROR"
}

Read-Host "Press Enter to exit"

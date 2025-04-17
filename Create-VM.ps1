# Create-VM.ps1 (Fixed)
function Log {
    param ([string]$M, [string]$T = "INFO")
    Write-Host "[$T] $M"
}

function Setup-VMTPM {
    param([string]$VMName)
    try {
        Log "Setting up TPM for $VMName"
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (!$vm) { Log "VM '$VMName' not found." "ERROR"; return $false }
        if ($vm.Generation -ne 2) { Log "VM '$VMName' not Gen 2." "ERROR"; return $false }
        
        if ($vm.State -ne "Off") {
            Log "Shutting down VM..." "WARN"
            Stop-VM -Name $VMName -Force
            $timeout = 60
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ((Get-VM -Name $VMName).State -ne "Off" -and $timer.Elapsed.TotalSeconds -lt $timeout) { Start-Sleep -s 2 }
            if ((Get-VM -Name $VMName).State -ne "Off") { Log "Shutdown failed." "ERROR"; return $false }
        }
        
        Log "Applying key protector"
        Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
        Log "Enabling TPM"
        Enable-VMTPM -VMName $VMName
        $tpmStatus = (Get-VMSecurity -VMName $VMName).TpmEnabled
        Log "TPM status: $tpmStatus"
        return $tpmStatus
    } catch {
        Log "TPM error: $_" "ERROR"
        return $false
    }
}

# Check admin rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Log "Requesting admin rights..." "WARN"
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$defaultPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"

# Get config (test or user input)
if ((Read-Host "Use test values? (Y/N)") -match "^[Yy]$") {
    $vmName = "TestVM"; $ramGB = 8; $cpuCount = 4; $storageGB = 128
    $userPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
    $isoPath = Read-Host "ISO path"
    Log "Using test values: VM=$vmName, RAM=${ramGB}GB, CPU=$cpuCount, Storage=${storageGB}GB"
} else {
    $vmName = Read-Host "VM name"
    do { $ramGB = Read-Host "RAM (GB, min 2)" } while ([int]$ramGB -lt 2)
    do { $cpuCount = Read-Host "CPU cores (min 1)" } while ([int]$cpuCount -lt 1)
    do { $storageGB = Read-Host "Storage (GB, min 20)" } while ([int]$storageGB -lt 20)
    $userPath = Read-Host "VHD location (default: $defaultPath)"
    $isoPath = Read-Host "ISO path"
}

# Check if VM exists
if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    Log "VM '$vmName' already exists." "ERROR"; Read-Host "Press Enter"; exit
}

# Setup paths
$ramBytes = [int64]$ramGB * 1GB
$storageBytes = [int64]$storageGB * 1GB
$vmPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $defaultPath } else { $userPath }
$vhdPath = "$vmPath$vmName.vhdx"

# Check for existing VHDX
if (Test-Path $vhdPath) {
    if ((Read-Host "VHDX exists. Delete? (Y/N)") -match "^[Yy]$") {
        Remove-Item $vhdPath -Force; Log "VHDX deleted."
    } else {
        Log "Canceled."; Read-Host "Press Enter"; exit
    }
}

# Create dir if needed
if (!(Test-Path $vmPath)) { New-Item -ItemType Directory -Path $vmPath | Out-Null }

try {
    # Create VM
    Log "Creating VM..."
    New-VM -Name $vmName -MemoryStartupBytes $ramBytes -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes $storageBytes
    Set-VMProcessor -VMName $vmName -Count $cpuCount
    Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes $ramBytes
    Set-VM -Name $vmName -CheckpointType Disabled
    Set-VMHost -EnableEnhancedSessionMode $False
    Disable-VMIntegrationService -VMName $vmName -Name "Guest Service Interface"

    # Enable TPM
    Log "Configuring TPM..."
    $tpmEnabled = Setup-VMTPM -VMName $vmName
    
    # Attach ISO
    $isoAttached = $false
    if (Test-Path $isoPath) {
        Log "Attaching ISO..."
        Add-VMDvdDrive -VMName $vmName -Path $isoPath
        $isoAttached = $true
        Log "ISO attached successfully."
    } else {
        Log "Invalid ISO path: $isoPath" "WARN"
    }
    
    # Summary
    Log "VM created: $vmName (Gen 2, ${cpuCount}CPU, ${ramGB}GB RAM, ${storageGB}GB disk, TPM: $(if($tpmEnabled){'Enabled'}else{'Failed'}), ISO: $(if($isoAttached){'Yes'}else{'No'}))"
} catch {
    Log "Error: $_" "ERROR"
}

Log "Script completed"
Read-Host "Press Enter to exit"

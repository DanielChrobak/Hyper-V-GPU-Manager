# Create-VM.ps1 (Enhanced Logging)
function Log {
    param ([string]$M, [string]$T = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp][$T] $M"
}

function Setup-VMTPM {
    param([string]$VMName)
    try {
        Log "Initiating TPM setup for $VMName"
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (!$vm) { Log "VM '$VMName' not found." "ERROR"; return $false }
        if ($vm.Generation -ne 2) { Log "VM '$VMName' is Generation $($vm.Generation), TPM requires Gen 2." "ERROR"; return $false }
        
        if ($vm.State -ne "Off") {
            Log "VM is currently $($vm.State). Initiating shutdown..." "WARN"
            Stop-VM -Name $VMName -Force
            $timeout = 60
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ((Get-VM -Name $VMName).State -ne "Off" -and $timer.Elapsed.TotalSeconds -lt $timeout) { 
                Start-Sleep -s 2 
                Log "Waiting for VM to shut down... ($([math]::Round($timer.Elapsed.TotalSeconds))s elapsed)" "DEBUG"
            }
            if ((Get-VM -Name $VMName).State -ne "Off") { 
                Log "VM shutdown timed out after $timeout seconds." "ERROR"
                return $false 
            }
            Log "VM successfully powered off after $([math]::Round($timer.Elapsed.TotalSeconds))s" "SUCCESS"
        }
        
        Log "Applying key protector to VM security configuration"
        Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
        Log "Enabling TPM module for VM"
        Enable-VMTPM -VMName $VMName
        $tpmStatus = (Get-VMSecurity -VMName $VMName).TpmEnabled
        Log "TPM configuration completed with status: $tpmStatus" "SUCCESS"
        return $tpmStatus
    } catch {
        Log "TPM configuration failed with exception: $_" "ERROR"
        return $false
    }
}

# Check admin rights
Log "Verifying administrative privileges"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Log "Script requires elevation. Requesting admin rights..." "WARN"
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Log "Administrative privileges confirmed" "SUCCESS"

$defaultPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
Log "Default VHD path: $defaultPath"

# Get config (test or user input)
Log "Collecting configuration parameters"
if ((Read-Host "Use test values? (Y/N)") -match "^[Yy]$") {
    $vmName = "TestVM"; $ramGB = 8; $cpuCount = 4; $storageGB = 128
    $userPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
    $isoPath = Read-Host "ISO path"
    Log "Configuration: Test mode with VM=$vmName, RAM=${ramGB}GB, CPU=$cpuCount, Storage=${storageGB}GB"
} else {
    $vmName = Read-Host "VM name"
    do { 
        $ramGB = Read-Host "RAM (GB, min 2)" 
        if ([int]$ramGB -lt 2) { Log "RAM must be at least 2GB" "WARN" }
    } while ([int]$ramGB -lt 2)
    
    do { 
        $cpuCount = Read-Host "CPU cores (min 1)" 
        if ([int]$cpuCount -lt 1) { Log "CPU count must be at least 1" "WARN" }
    } while ([int]$cpuCount -lt 1)
    
    do { 
        $storageGB = Read-Host "Storage (GB, min 20)" 
        if ([int]$storageGB -lt 20) { Log "Storage must be at least 20GB" "WARN" }
    } while ([int]$storageGB -lt 20)
    
    $userPath = Read-Host "VHD location (default: $defaultPath)"
    $isoPath = Read-Host "ISO path"
    Log "Configuration: Custom with VM=$vmName, RAM=${ramGB}GB, CPU=$cpuCount, Storage=${storageGB}GB"
}

# Check if VM exists
Log "Checking for existing VM with name '$vmName'"
if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    Log "VM '$vmName' already exists. Cannot proceed with creation." "ERROR"
    Read-Host "Press Enter"
    exit
}
Log "VM name check passed" "SUCCESS"

# Setup paths
$ramBytes = [int64]$ramGB * 1GB
$storageBytes = [int64]$storageGB * 1GB
$vmPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $defaultPath } else { $userPath }
$vhdPath = "$vmPath$vmName.vhdx"
Log "Calculated values: RAM=$ramBytes bytes, Storage=$storageBytes bytes"
Log "VHD will be created at: $vhdPath"

# Check for existing VHDX
Log "Checking for existing VHDX at path: $vhdPath"
if (Test-Path $vhdPath) {
    Log "VHDX already exists at target location" "WARN"
    if ((Read-Host "VHDX exists. Delete? (Y/N)") -match "^[Yy]$") {
        Remove-Item $vhdPath -Force
        Log "Existing VHDX deleted successfully" "SUCCESS"
    } else {
        Log "User chose not to delete existing VHDX. Operation canceled." "INFO"
        Read-Host "Press Enter"
        exit
    }
}

# Create dir if needed
Log "Verifying VHD directory exists: $vmPath"
if (!(Test-Path $vmPath)) { 
    Log "Creating directory: $vmPath"
    New-Item -ItemType Directory -Path $vmPath | Out-Null 
    Log "Directory created successfully" "SUCCESS"
}

try {
    # Create VM
    Log "Initiating VM creation process"
    Log "Creating VM with name: $vmName, RAM: $ramBytes bytes, Generation: 2, VHD: $vhdPath, Size: $storageBytes bytes"
    New-VM -Name $vmName -MemoryStartupBytes $ramBytes -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes $storageBytes
    Log "VM created successfully. Configuring processor settings..." "SUCCESS"
    Set-VMProcessor -VMName $vmName -Count $cpuCount
    Log "Processor configured with $cpuCount cores. Configuring memory settings..."
    Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes $ramBytes
    Log "Memory configured. Disabling checkpoints..."
    Set-VM -Name $vmName -CheckpointType Disabled
    Log "Disabling enhanced session mode..."
    Set-VMHost -EnableEnhancedSessionMode $False
    Log "Disabling Guest Service Interface..."
    Disable-VMIntegrationService -VMName $vmName -Name "Guest Service Interface"
    Log "Base VM configuration completed" "SUCCESS"

    # Enable TPM
    Log "Beginning TPM configuration process"
    $tpmEnabled = Setup-VMTPM -VMName $vmName
    Log "TPM setup completed with result: $tpmEnabled"
    
    # Attach ISO
    $isoAttached = $false
    Log "Checking ISO path: $isoPath"
    if (Test-Path $isoPath) {
        Log "ISO file found. Attaching to VM..."
        Add-VMDvdDrive -VMName $vmName -Path $isoPath
        $isoAttached = $true
        Log "ISO attached successfully: $isoPath" "SUCCESS"
    } else {
        Log "ISO file not found at specified path: $isoPath" "WARN"
    }
    
    # Summary
    Log "VM CREATION SUMMARY" "SUCCESS"
    Log "Name: $vmName" "SUCCESS"
    Log "Generation: 2" "SUCCESS"
    Log "CPU: $cpuCount cores" "SUCCESS"
    Log "RAM: ${ramGB}GB" "SUCCESS"
    Log "Storage: ${storageGB}GB" "SUCCESS"
    Log "TPM: $(if($tpmEnabled){'Enabled'}else{'Failed'})" "$(if($tpmEnabled){'SUCCESS'}else{'WARN'})"
    Log "ISO: $(if($isoAttached){'Attached'}else{'Not attached'})" "$(if($isoAttached){'SUCCESS'}else{'WARN'})"
} catch {
    Log "VM creation failed with exception: $_" "ERROR"
    Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
}

Log "Script execution completed"
Read-Host "Press Enter to exit"

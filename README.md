# GPU Virtualization and Partitioning Manager

A PowerShell-based Hyper-V management utility automating GPU partitioning, universal GPU driver detection, and driver injection for virtual machines.

## Overview

The Unified VM Manager automates three critical workflows:
1. **GPU Partitioning** - Allocates GPU resources to VMs with configurable VRAM percentages
2. **Universal Driver Detection** - Identifies GPU drivers from any vendor through registry-based INF scanning
3. **Automated Driver Injection** - Copies drivers directly into VM disk images

The tool handles NVIDIA, AMD, Intel Arc, and integrated graphics using vendor-agnostic architecture. Extensively tested with NVIDIA GPUs; other vendors follow the same INF-based detection system.

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10 Pro 20H1+ | Windows 11 Pro (latest) |
| RAM | 16GB | 32GB+ |
| CPU | 6 cores | 8+ cores |
| GPU | 4GB VRAM | 8GB+ |
| Storage | 128GB SSD | 256GB+ NVMe |

**Prerequisites:** Hyper-V enabled, Administrator privileges, PowerShell 5.1+, GPU drivers installed on host, VT-x/AMD-V enabled in BIOS

## Installation

### 1. Enable Hyper-V
```powershell
PS> Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All
```
Restart required.

### 2. Verify GPU Support
```powershell
PS> Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notlike "*Microsoft*" } | Select-Object Name, DriverVersion
PS> nvidia-smi  # For NVIDIA GPUs
```

### 3. Configure Script Execution
```powershell
PS> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 4. Run the Manager
```powershell
PS> .\Unified-VM-Manager.ps1
```

## Architecture and Internal Operations

### GPU Device Detection

GPUs discovered via WMI `Win32_PnPSignedDriver` class, filtered by Display devices. Vendor-agnostic approach works with any registered display adapter.

```powershell
$gpuDrivers = Get-WmiObject Win32_PnPSignedDriver -ErrorAction SilentlyContinue | 
    Where-Object { $_.DeviceClass -eq "Display" }
```

### INF Registry Resolution

Windows stores driver metadata in registry at `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`. The tool queries this path to locate INF files:

```powershell
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
foreach ($subkey in (Get-ChildItem $registryPath)) {
    $props = Get-ItemProperty -Path $subkey.PSPath
    if ($props.MatchingDeviceId -like "*GPU-ID*") {
        $infFilePath = "C:\Windows\INF\$($props.InfPath)"
        break
    }
}
```

### INF File Parsing

INF files are parsed to extract referenced driver files using regex patterns for .sys, .dll, .exe, .cat, .inf, .bin, .vp, .cpa files:

```powershell
$filePatterns = @('[\\w\\-\\.]+\\.sys', '[\\w\\-\\.]+\\.dll', '[\\w\\-\\.]+\\.exe', '[\\w\\-\\.]+\\.cat')
$infContent = Get-Content $infFilePath -Raw
foreach ($pattern in $filePatterns) {
    $matches = [regex]::Matches($infContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $matches) {
        if (-not ($referencedFiles -contains $match.Value)) {
            $referencedFiles += $match.Value
        }
    }
}
```

### Multi-Location File Discovery

Files searched in standard Windows locations:
- `C:\Windows\System32\DriverStore\FileRepository` (entire folders copied for integrity)
- `C:\Windows\System32` (individual files)
- `C:\Windows\SysWow64` (individual files)

**DriverStore vs. Individual Files:**
- **DriverStore folders** contain thousands of files per driver version; entire folders copied to preserve package integrity
- **Individual files** copied directly to VM's System32/SysWow64

### Virtual Disk Mounting

VHD/VHDX mounted without drive letter to avoid conflicts:

```powershell
$mounted = Mount-VHD $VHDPath -NoDriveLetter -PassThru
Update-Disk $mounted.DiskNumber
$partition = Get-Partition -DiskNumber $mounted.DiskNumber | 
    Where-Object { $_.Size -gt 10GB } | 
    Select-Object -First 1
$mountPoint = "C:\Temp\VMMount_$(Get-Random)"
New-Item $mountPoint -ItemType Directory -Force | Out-Null
Add-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint
Test-Path "$mountPoint\Windows" # Verify Windows installation
```

### Driver Installation

**Stage 1: Copy DriverStore folders**
```powershell
$hostDriverStorePath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
New-Item -Path $hostDriverStorePath -ItemType Directory -Force | Out-Null
foreach ($storeFolder in $driverData.StoreFolders) {
    $folderName = Split-Path -Leaf $storeFolder
    Copy-Item -Path $storeFolder -Destination "$hostDriverStorePath\$folderName" -Recurse -Force
}
```

**Stage 2: Copy individual system files**
```powershell
foreach ($file in $driverData.Files) {
    $destPath = "$mountPoint$($file.DestPath)"
    New-Item -Path (Split-Path -Parent $destPath) -ItemType Directory -Force | Out-Null
    Copy-Item -Path $file.FullPath -Destination $destPath -Force
}
```

### Clean Unmounting
```powershell
Remove-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint
Dismount-VHD $VHDPath
Remove-Item $mountPoint -Recurse -Force
```

### GPU Partition Configuration

Allocates GPU resources via partition values (1-100% percentage):

```powershell
$percentage = 50
$maxValue = [int](($percentage / 100) * 1.0e+09)    # 500,000,000
$optimalValue = $maxValue - 1
Set-VMGpuPartitionAdapter $VMName `
    -MinPartitionVRAM 1 -MaxPartitionVRAM $maxValue -OptimalPartitionVRAM $optimalValue `
    -MinPartitionEncode 1 -MaxPartitionEncode $maxValue -OptimalPartitionEncode $optimalValue `
    -MinPartitionDecode 1 -MaxPartitionDecode $maxValue -OptimalPartitionDecode $optimalValue `
    -MinPartitionCompute 1 -MaxPartitionCompute $maxValue -OptimalPartitionCompute $optimalValue
Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
```

| Partition Type | Controls |
|----------------|----------|
| VRAM | Video memory access |
| Encode | Hardware video encoding |
| Decode | Hardware video decoding |
| Compute | Compute/CUDA operations |

## User Interface

### Navigation

Menu system uses arrow keys for selection. UP/DOWN to move, ENTER to confirm (wraps around).

### Logging Output

Timestamped, color-coded messages:
- `>` Cyan (INFO)
- `+` Green (SUCCESS)
- `!` Yellow (WARN)
- `X` Red (ERROR)
- `~` Magenta (HEADER)

## Menu Options

### Create New VM

Launches VM creation with preset configurations.

**Presets:**
| Preset | RAM | CPUs | Storage |
|--------|-----|------|---------|
| Gaming | 16GB | 8 | 256GB |
| Development | 8GB | 4 | 128GB |
| ML Training | 32GB | 12 | 512GB |
| Custom | User-defined | User-defined | User-defined |

**VM Configuration:**
- Memory: Static allocation (no dynamic memory)
- Generation: 2 (UEFI)
- Security: Secure Boot enabled, TPM 2.0 enabled
- Checkpoints: Disabled
- Boot order: DVD first, HDD second

### Configure GPU Partition

Adds GPU partition adapter and allocates percentage of GPU resources (1-100%).

### Inject GPU Drivers (Auto-Detect)

Automatically detects and injects GPU drivers into selected VM disk image.

**Process:**
1. User selects target VM
2. Auto-detects available GPUs
3. Locates INF file from registry
4. Parses INF for file references (typically 200-300 unique files)
5. Searches system locations for each file
6. Copies DriverStore folders (preserves integrity)
7. Copies individual system files
8. Unmounts disk safely

**What Gets Copied:**
- All driver files referenced in GPU INF
- Entire DriverStore folders
- System library files (.dll, .sys, .exe, .cat, .inf, .bin, .vp, .cpa)

**What Doesn't Get Copied:**
- Application-specific dependencies (install separately in VM)
- CUDA runtime libraries (install CUDA toolkit in VM)
- Game-specific or application-specific libraries

**Multi-GPU Support:** Displays all available GPUs; user selects which GPU's drivers to inject.

### Complete Setup

Orchestrates full workflow: VM creation, GPU partition configuration, and driver injection preparation.

Typical post-setup workflow:
1. Complete Setup creates VM + partitions GPU
2. Open Hyper-V Manager - start VM and install Windows OS
3. Shutdown VM after Windows installation
4. Inject GPU Drivers (Auto-Detect)
5. Start VM - GPU drivers now loaded
6. Install applications

### Update VM Drivers (Auto-Detect)

Synchronizes VM GPU drivers with host system. Useful after updating host GPU drivers. Process identical to "Inject GPU Drivers."

### List VMs & GPU Info

Displays comprehensive inventory of all VMs and host GPU information with VRAM detection using vendor-specific tools.

**VRAM Detection Methods:**
- **NVIDIA:** `nvidia-smi --query-gpu=memory.total` (most accurate)
- **AMD:** `rocm-smi --showmeminfo` (when ROCm installed)
- **Intel Arc/iGPU:** Windows Registry `HardwareInformation.qxvram`
- **Fallback:** WMI `AdapterRAM` (unreliable >4GB)

### Copy VM Apps to Downloads

Copies application zip files from "VM Apps" folder (in script directory) to VM's Downloads folder.

**Requirements:**
1. "VM Apps" folder in script directory
2. Zip files inside folder
3. VM powered off

**Files copied to:** `C:\Users\[Username]\Downloads\VM Apps\`

## Known Limitations

### Application Compatibility and DLL Dependencies

Tool automates baseline driver installation but doesn't resolve per-application issues.

**Supported:**
- DirectX 9/10/11/12 applications
- Standard display driver rendering
- Basic GPU initialization and VRAM allocation

**Not Supported:**
- CUDA compute libraries (install CUDA toolkit inside VM)
- Application-specific dependencies
- OpenGL rendering (translated through DirectX 12 - may have glitches)
- Vulkan API (no GPU-PV support)
- DLSS and Frame Generation features

**Troubleshooting Application DLL Errors:**

If application fails with DLL error, manually copy missing library:
```powershell
PS> Copy-Item "C:\Windows\System32\curand64.dll" "C:\Temp\VMMount_12345\Windows\System32\"
```

### OpenGL Applications

GPU-PV translates OpenGL to DirectX 12, causing performance degradation and rendering glitches. Use DirectX version if available.

### Vulkan and Advanced Features

Not supported: Vulkan API, DLSS, Frame Generation, Explicit GPU scheduling.

## Workflow Examples

### Gaming VM Setup
```powershell
1. Create New VM (Gaming preset)
2. Install Windows inside VM
3. Inject GPU Drivers (Auto-Detect)
4. Configure GPU Partition (50%)
5. Result: GPU-accelerated DirectX rendering
```

### Multi-GPU Load Balancing
```powershell
# Host with RTX 4090 + RTX 4080 Super
- Gaming-VM: RTX 4090 at 50%
- Dev-VM: RTX 4080 Super at 40%
# Both VMs access different GPUs simultaneously
```

### Development VM with Unreal Engine
```powershell
1. Complete Setup (Development preset)
2. Install Windows + GPU drivers
3. Download Unreal Engine inside VM
# GPU memory reserved via partitioning; near-native DirectX performance
```

### Machine Learning VM with CUDA
```powershell
1. Complete Setup (ML Training preset - 32GB RAM, 75% GPU)
2. Install Windows + GPU drivers
3. Inside VM: Install CUDA toolkit (not included with drivers)
   PS> # Download from https://developer.nvidia.com/cuda-downloads
4. Install PyTorch, TensorFlow
# CUDA compute operations now available for ML workloads
```

## Troubleshooting

### GPU Not Detected in VM

**Cause:** Drivers not copied or Windows partition not detected

**Resolution:**
```powershell
PS> Get-VMGpuPartitionAdapter -VMName GamingVM  # Verify partition configured
# If no output, run "Configure GPU Partition" from menu
# Verify Windows installation in Device Manager (may show PCI Controller with warning)
```

### Driver Injection Fails with "Windows Not Installed"

**Cause:** VM disk lacks Windows installation

**Resolution:**
1. Create VM with ISO
2. Boot into Windows installation inside Hyper-V Manager
3. Complete Windows Setup
4. Shutdown VM
5. Run "Inject GPU Drivers (Auto-Detect)"

### Multiple GPUs Show, Wrong One Selected

**Cause:** GPU driver info not properly registered in registry

**Resolution:**
```powershell
PS> nvidia-smi  # Verify NVIDIA GPU detection
PS> Get-WmiObject Win32_VideoController | Select Name, DriverVersion  # Check all GPUs
# Update drivers via Device Manager, manufacturer website, or GeForce Experience/Radeon Software
# Reboot system
# Retry driver injection
```

### Insufficient Disk Space During Driver Copy

**Cause:** VM virtual disk full

**Resolution:**
```powershell
PS> $vm = Get-VM MyVM
PS> $disk = Get-VHD -Path $vm.HardDrives[0].Path
PS> Resize-VirtualDisk -Path $disk.Path -SizeBytes 500GB
# Or delete unused files inside VM
```

## PowerShell Examples

### Programmatic VM Creation
```powershell
$config = @{
    Name = "DataVM"
    RAM = 16
    CPU = 8
    Storage = 512
    Path = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
    ISO = $null
}
$vmName = Initialize-VM -Config $config
```

### Query VM GPU Allocation
```powershell
$vms = Get-VM
foreach ($vm in $vms) {
    $gpuAdapter = Get-VMGpuPartitionAdapter $vm.Name -ErrorAction SilentlyContinue
    if ($gpuAdapter) {
        $percent = [math]::Round(($gpuAdapter.MaxPartitionVRAM / 1.0e+09) * 100)
        Write-Host "$($vm.Name): $percent% GPU"
    } else {
        Write-Host "$($vm.Name): No GPU partition"
    }
}
```

### List All Host GPUs with VRAM
```powershell
$gpus = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq "Display" }
foreach ($gpu in $gpus) {
    Write-Host "Name: $($gpu.DeviceName)"
    Write-Host "Driver: $($gpu.DriverVersion)"
    Write-Host "Provider: $($gpu.DriverProviderName)"
    if ($gpu.DeviceName -like "*NVIDIA*") {
        $vram = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        if ($vram) { Write-Host "VRAM: $([int]$vram / 1024) GB (nvidia-smi)" }
    }
    Write-Host "---"
}
```

## Technical Details

### Virtual Disk Mounting Sequence
```powershell
Mount-VHD -NoDriveLetter                    # Mount without drive letter
Update-Disk -DiskNumber $num                # Refresh partition info
Get-Partition -DiskNumber $num              # Enumerate partitions
Add-PartitionAccessPath                     # Mount to temporary folder
Test-Path "$mount\Windows"                  # Verify OS installation
Remove-PartitionAccessPath                  # Unmount partition
Dismount-VHD -Path $vhd                    # Dismount VHD
Remove-Item $mount -Recurse -Force         # Clean temporary folder
```

### GPU Partition Value Calculation
```powershell
# For 50% GPU allocation:
$percentage = 50
$maxValue = [int](($percentage / 100) * 1.0e+09)  # 500,000,000
# Applied to VRAM, Encode, Decode, Compute
```

### Memory-Mapped I/O Configuration
```powershell
Set-VM -VMName MyVM `
    -GuestControlledCacheTypes $true `     # Allow guest to control cache
    -LowMemoryMappedIoSpace 1GB `          # Low address space for I/O
    -HighMemoryMappedIoSpace 32GB          # High address space for GPU VRAM
```

Maps physical GPU memory into guest VM's address space for direct GPU communication.

## Advanced Configuration

### Custom VM Storage Path

By default, VMs stored in `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`. To use different path:

```powershell
# During VM creation:
PS> Storage Path: D:\Hyper-V\VMs\MyVM.vhdx

# Or programmatically:
$config.Path = "D:\Hyper-V\VMs\"
$vmName = Initialize-VM -Config $config
```

### Changing GPU Allocation After VM Creation
```powershell
$vmName = "GamingVM"
$newPercent = 75
if ((Get-VM $vmName).State -ne "Off") {
    Stop-VM $vmName -Force
}
Set-GPUPartition -VMName $vmName -Percentage $newPercent
```

### Viewing VM Configuration
```powershell
$vm = Get-VM -Name "GamingVM"
Write-Host "Name: $($vm.Name)"
Write-Host "State: $($vm.State)"
Write-Host "RAM: $([math]::Round($vm.MemoryAssigned / 1GB)) GB"
Write-Host "CPUs: $($vm.ProcessorCount)"
$gpu = Get-VMGpuPartitionAdapter -VMName "GamingVM" -ErrorAction SilentlyContinue
if ($gpu) {
    $percent = [math]::Round(($gpu.MaxPartitionVRAM / 1.0e+09) * 100)
    Write-Host "GPU: $percent%"
}
```

## Credits

Built on GPU-PV (GPU Paravirtualization) technology by Microsoft for Hyper-V and Windows Server. Driver detection and injection architecture supports universal GPU support through vendor-agnostic INF registry resolution and file discovery. Extensively tested with NVIDIA GPUs; AMD Radeon and Intel Arc driver detection follow same registry and INF parsing mechanisms.

## License

Provided as-is for personal and educational use. No warranty. Use at your own risk.

**Disclaimer:** GPU virtualization depends on compatible hardware and may not work with all GPU models/driver versions. Application compatibility varies - tool automates initial driver setup but cannot prevent per-app issues or missing dependencies. Always backup important data before VM operations.

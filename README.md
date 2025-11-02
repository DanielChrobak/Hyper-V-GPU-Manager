# GPU Virtualization and Partitioning Manager

A PowerShell-based Hyper-V management utility designed to automate GPU partitioning, universal GPU driver detection, and driver injection for virtual machines. This tool consolidates VM creation, GPU resource allocation, and cross-vendor GPU driver management into a streamlined command-line interface.

## Overview

The Unified VM Manager simplifies Hyper-V GPU virtualization by automating three critical workflows:

1. **GPU Partitioning** - Allocates GPU resources to VMs with configurable VRAM percentages
2. **Universal Driver Detection** - Identifies GPU drivers from any vendor through registry-based INF scanning
3. **Automated Driver Injection** - Copies drivers directly into VM disk images without manual intervention

The tool handles GPU detection and driver extraction from NVIDIA, AMD, Intel Arc, and integrated graphics using a vendor-agnostic architecture. Current testing and validation has been performed extensively with NVIDIA GPUs; other vendors' drivers follow the same INF-based detection system and should function correctly.

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10 Pro 20H1+ | Windows 11 Pro (latest build) |
| RAM | 16GB total | 32GB+ |
| CPU | 6 cores | 8+ cores (Ryzen 5 5600X / i5-12400+) |
| GPU | 4GB VRAM | 8GB+ (RTX 2060 Super or better) |
| Storage | 128GB SSD available | 256GB+ NVMe SSD |

**Prerequisites:**
- Hyper-V enabled (Windows Pro/Enterprise only)
- Administrator privileges
- PowerShell 5.1 or later
- GPU drivers installed on host system
- VT-x or AMD-V enabled in BIOS

## Installation

### 1. Enable Hyper-V

Open PowerShell as Administrator and execute:

```powershell
PS> Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All
```

System restart required after enabling Hyper-V.

### 2. Verify GPU Support

Verify GPU drivers are installed:

```powershell
PS> Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notlike "*Microsoft*" } | Select-Object Name, DriverVersion

Name                    DriverVersion
----                    ---------
NVIDIA GeForce RTX 4090 32.0.15.8129
```

For NVIDIA GPUs, verify with nvidia-smi:

```powershell
PS> nvidia-smi

+-----------------------------------------------------------------------------+
| NVIDIA-SMI 551.78       Driver Version: 551.78                             |
+-----------------------------------------------------------------------------+
| GPU  Name            TCC/WDDM  Memory-Usage  Temp  Perf  Pwr:Usage/Cap    |
|  0   NVIDIA RTX 4090  WDDM      100MiB/24GB  35C   P0   85W / 575W        |
+-----------------------------------------------------------------------------+
```

### 3. Configure Script Execution

Allow PowerShell script execution:

```powershell
PS> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 4. Run the Manager

```powershell
PS> .\Unified-VM-Manager.ps1
```

The script automatically requests administrator elevation if not already running with elevated privileges.

## Architecture and Internal Operations

### GPU Device Detection

The tool discovers GPUs through Windows Management Instrumentation (WMI), accessing the `Win32_PnPSignedDriver` class filtered by Display devices:

```powershell
# GPU device enumeration
$gpuDrivers = Get-WmiObject Win32_PnPSignedDriver -ErrorAction SilentlyContinue | 
    Where-Object { $_.DeviceClass -eq "Display" }

foreach ($gpu in $gpuDrivers) {
    Write-Host "GPU: $($gpu.DeviceName)"
    Write-Host "Driver Version: $($gpu.DriverVersion)"
    Write-Host "Provider: $($gpu.DriverProviderName)"
}
```

This approach is vendor-agnostic and works with any display adapter that properly registers with Windows.

### INF Registry Resolution

Windows maintains driver metadata in the registry under the display adapter class registry key. The tool queries this path to locate the INF file:

```powershell
# Registry path for all display adapters (universal GUID)
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"

# Example subkey structure:
# HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000
#   ├── DriverDesc: "NVIDIA RTX 4090"
#   ├── MatchingDeviceId: "PCI\VEN_10DE&DEV_2684&SUBSYS_12381462"
#   ├── DriverVersion: "32.0.15.8129"
#   └── InfPath: "oem123.inf"
```

The script enumerates these subkeys and matches them against the selected GPU:

```powershell
foreach ($subkey in $driverSubkeys) {
    $props = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
    
    if ($props.MatchingDeviceId -like "*$($GPU.DeviceID)*") {
        $infFileName = $props.InfPath  # e.g., "oem123.inf"
        break
    }
}
```

Once the INF filename is identified, the full path is constructed:

```powershell
$infFilePath = "C:\Windows\INF\$infFileName"
```

### INF File Parsing

INF files are text-based driver description files containing file references. The tool parses INF content to extract all required driver files using regular expressions:

```powershell
# INF file example content (simplified):
# [SourceDisksFiles]
# nv4_mini.sys = 1
# nvapi64.dll = 1
# nvlddmkm.sys = 1
# d3d12core.dll = 1

# Regex patterns for driver file types
$filePatterns = @(
    '[\w\-\.]+\.sys',      # System drivers: nvlddmkm.sys, nv4_mini.sys
    '[\w\-\.]+\.dll',      # Dynamic libraries: nvapi64.dll, nvd3dum.dll
    '[\w\-\.]+\.exe',      # Executables: nvidia-smi.exe, nvcuda.exe
    '[\w\-\.]+\.cat',      # Catalog files: nvidia.cat
    '[\w\-\.]+\.inf',      # INF files: nvdmi.inf
    '[\w\-\.]+\.bin',      # Binary resources
    '[\w\-\.]+\.vp',       # Vertex programs
    '[\w\-\.]+\.cpa'       # Compute architecture
)

$infContent = Get-Content $infFilePath -Raw
$referencedFiles = @()

foreach ($pattern in $filePatterns) {
    $matches = [regex]::Matches($infContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    
    foreach ($match in $matches) {
        if ($match.Value -and -not ($referencedFiles -contains $match.Value)) {
            $referencedFiles += $match.Value
        }
    }
}

# Result: $referencedFiles contains all unique filenames referenced in INF
# Example: @("nvlddmkm.sys", "nvapi64.dll", "nvd3dum.dll", ...)
```

### Multi-Location File Discovery

Extracted filenames are then searched across standard Windows driver locations:

```powershell
$searchPaths = @(
    @{ Path = "C:\Windows\System32\DriverStore\FileRepository"; Type = "DriverStore"; Recurse = $true }
    @{ Path = "C:\Windows\System32"; Type = "System32"; Recurse = $false }
    @{ Path = "C:\Windows\SysWow64"; Type = "SysWow64"; Recurse = $false }
)

# Search algorithm for each referenced file
foreach ($fileName in $referencedFiles) {
    foreach ($searchPath in $searchPaths) {
        $result = Get-ChildItem -Path $searchPath.Path `
                                -Filter $fileName `
                                -Recurse:$searchPath.Recurse `
                                -ErrorAction SilentlyContinue | 
                 Select-Object -First 1
        
        if ($result) {
            # File found - track location and type
            if ($searchPath.Type -eq "DriverStore") {
                # DriverStore folders are copied wholesale (100+ files each)
                $driverStoreFolders += $result.DirectoryName
            } else {
                # Individual system files
                $foundFiles += [PSCustomObject]@{
                    FileName = $fileName
                    FullPath = $result.FullName
                    DestPath = $result.FullName.Replace("C:", "")
                }
            }
            break
        }
    }
}
```

**DriverStore vs. Individual Files:**

- **DriverStore folders** (`C:\Windows\System32\DriverStore\FileRepository\`) contain thousands of files organized by driver version. Rather than extracting individual files, entire folders are copied to preserve driver package integrity.

- **Individual files** in `C:\Windows\System32` and `C:\Windows\SysWow64` are copied directly to their corresponding locations in the VM.

### Virtual Disk Mounting

VHD/VHDX files are mounted without a drive letter to avoid conflicts:

```powershell
# Mount VHD without drive letter assignment
$mounted = Mount-VHD $VHDPath -NoDriveLetter -PassThru -ErrorAction Stop

# Refresh disk information to discover partitions
Update-Disk $mounted.DiskNumber -ErrorAction SilentlyContinue

# Identify Windows partition (typically > 10GB)
$partition = Get-Partition -DiskNumber $mounted.DiskNumber | 
    Where-Object { $_.Size -gt 10GB } | 
    Sort-Object Size -Descending | 
    Select-Object -First 1

# Create temporary mount point
$mountPoint = "C:\Temp\VMMount_$(Get-Random)"
New-Item $mountPoint -ItemType Directory -Force | Out-Null

# Mount partition to temporary path
Add-PartitionAccessPath -DiskNumber $mounted.DiskNumber `
                        -PartitionNumber $partition.PartitionNumber `
                        -AccessPath $mountPoint

# Verify Windows installation
if (!(Test-Path "$mountPoint\Windows")) {
    throw "Windows directory not found - invalid Windows installation"
}
```

After mounting, the directory structure looks like:

```
C:\Temp\VMMount_12345\
├── Windows\
│   ├── System32\
│   │   ├── HostDriverStore\FileRepository\
│   │   ├── nv*.dll (copied)
│   │   ├── nv*.sys (copied)
│   │   └── ...
│   ├── SysWow64\
│   └── ...
├── Program Files\
├── Users\
└── ...
```

### Driver Installation

Driver files are copied to their corresponding VM locations in two stages:

**Stage 1: DriverStore Folders**

```powershell
$hostDriverStorePath = "$mountPoint\Windows\System32\HostDriverStore\FileRepository"
New-Item -Path $hostDriverStorePath -ItemType Directory -Force | Out-Null

# Copy each DriverStore folder wholesale
foreach ($storeFolder in $driverData.StoreFolders) {
    $folderName = Split-Path -Leaf $storeFolder
    $destFolder = Join-Path $hostDriverStorePath $folderName
    
    Copy-Item -Path $storeFolder `
              -Destination $destFolder `
              -Recurse -Force
}
```

**Stage 2: Individual System Files**

```powershell
# Copy system files to VM's System32 and SysWow64
foreach ($file in $driverData.Files) {
    $destPath = "$mountPoint$($file.DestPath)"
    $destDir = Split-Path -Parent $destPath
    
    # Create parent directory if needed
    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    
    # Copy file
    Copy-Item -Path $file.FullPath `
              -Destination $destPath `
              -Force
}
```

### Clean Unmounting

After driver installation, the disk is safely unmounted:

```powershell
# Remove partition access path
Remove-PartitionAccessPath -DiskNumber $mounted.DiskNumber `
                          -PartitionNumber $partition.PartitionNumber `
                          -AccessPath $mountPoint

# Dismount VHD
Dismount-VHD $VHDPath

# Remove temporary mount directory
Remove-Item $mountPoint -Recurse -Force
```

### GPU Partition Configuration

GPU partitioning allocates GPU resources by setting memory partition values in Hyper-V:

```powershell
# User specifies allocation percentage: 50%

# Calculate partition values
$percentage = 50
$maxValue = [int](($percentage / 100) * 1000000000)    # 500,000,000
$optimalValue = $maxValue - 1                            # 499,999,999
$minValue = 1

# Configure GPU partition adapter
Set-VMGpuPartitionAdapter $VMName `
    -MinPartitionVRAM 1 `
    -MaxPartitionVRAM $maxValue `
    -OptimalPartitionVRAM $optimalValue `
    -MinPartitionEncode 1 `
    -MaxPartitionEncode $maxValue `
    -OptimalPartitionEncode $optimalValue `
    -MinPartitionDecode 1 `
    -MaxPartitionDecode $maxValue `
    -OptimalPartitionDecode $optimalValue `
    -MinPartitionCompute 1 `
    -MaxPartitionCompute $maxValue `
    -OptimalPartitionCompute $optimalValue

# Configure memory-mapped I/O for GPU access
Set-VM $VMName `
    -GuestControlledCacheTypes $true `
    -LowMemoryMappedIoSpace 1GB `
    -HighMemoryMappedIoSpace 32GB
```

The four partition types control different GPU capabilities:

| Partition Type | Controls | Units |
|----------------|----------|-------|
| VRAM | Video memory access | Bytes allocated |
| Encode | Hardware video encoding | Encoding operations per second |
| Decode | Hardware video decoding | Decoding operations per second |
| Compute | Compute/CUDA operations | Compute capacity |

Each type has minimum, optimal, and maximum values. The allocation percentage scales all four proportionally.

## User Interface

### Navigation

The menu system uses arrow keys for selection:

```
  > MAIN MENU
  |  (Use UP/DOWN arrows, ENTER to select)
  |
  |     Create New VM
  |  >> Configure GPU Partition      [green highlight, currently selected]
  |     Inject GPU Drivers (Auto-Detect)
  |     Complete Setup (VM + GPU + Drivers)
  |     Update VM Drivers (Auto-Detect)
  |     List VMs & GPU Info
  |     Copy VM Apps to Downloads
  |     Exit
  |
  >==========================================================================
```

- **UP Arrow** - Move selection up (wraps to bottom)
- **DOWN Arrow** - Move selection down (wraps to top)
- **ENTER** - Confirm selection

### Logging Output

All operations produce timestamped, color-coded log messages:

```
  [14:23:45] > GPU: NVIDIA RTX 4090                                    [Cyan]
  [14:23:45] + Found INF: oem123.inf                                   [Green - Success]
  [14:23:46] > Reading INF file...                                     [Cyan]
  [14:23:47] ! Could not find GPU in registry                          [Yellow - Warning]
  [14:23:48] X INF file not found: C:\Windows\INF\oem456.inf          [Red - Error]
```

Log levels:

| Level | Symbol | Color | Usage |
|-------|--------|-------|-------|
| INFO | > | Cyan | General operations |
| SUCCESS | + | Green | Completed successfully |
| WARN | ! | Yellow | Non-fatal issues |
| ERROR | X | Red | Failures requiring attention |
| HEADER | ~ | Magenta | Section headers |

## Menu Options Reference

### Create New VM

Launches VM creation with preset or custom configuration. Creates a Generation 2 VM with UEFI firmware, Secure Boot, and TPM 2.0 support.

```powershell
PS> (Select "Create New VM" from menu)
PS> (Select preset: Gaming | Development | ML Training | Custom)
PS> VM Name (default: Gaming-VM): MyGameVM
PS> ISO Path (Enter to skip): C:\ISOs\Windows11Pro.iso
```

**Preset Configurations:**

| Preset | RAM | CPUs | Storage |
|--------|-----|------|---------|
| Gaming | 16GB | 8 | 256GB |
| Development | 8GB | 4 | 128GB |
| ML Training | 32GB | 12 | 512GB |
| Custom | User-defined | User-defined | User-defined |

**VM Configuration Details:**

```powershell
# Memory: Static allocation (no dynamic memory)
Set-VMMemory -DynamicMemoryEnabled $false

# Processor: User-specified cores
Set-VMProcessor -Count 8

# Checkpoints: Disabled
Set-VM -CheckpointType Disabled

# Generation: 2 (UEFI)
New-VM -Generation 2

# Security: Secure Boot enabled, TPM 2.0 enabled
Set-VMFirmware -EnableSecureBoot On
Enable-VMTPM

# Boot order: DVD drive first, HDD second (allows Windows installation from ISO)
Set-VMFirmware -BootOrder $dvdDrive, $hardDrive
```

### Configure GPU Partition

Adds GPU partition adapter to a VM and allocates a percentage of GPU resources.

```powershell
PS> (Select "Configure GPU Partition" from menu)
PS> (Arrow keys to select VM from list)
PS> GPU Allocation % (1-100): 50
```

Displays selectable VM list with current configuration:

```
SELECT VIRTUAL MACHINE

  [1] Gaming-VM | State: Off | RAM: 16GB | CPU: 8 | GPU: None
  [2] Dev-VM | State: Off | RAM: 8GB | CPU: 4 | GPU: 25%
  [3] ML-VM | State: Running | RAM: 32GB | CPU: 12 | GPU: 60%
  [4] < Cancel >
```

### Inject GPU Drivers (Auto-Detect)

Automatically detects GPU drivers from host system and injects them into selected VM disk image. Uses vendor-specific tools and universal registry detection to find accurate driver information.

```powershell
PS> (Select "Inject GPU Drivers (Auto-Detect)" from menu)
PS> (Arrow keys to select target VM)
```

**GPU Selection (Multi-GPU Systems):**

```
SELECT GPU DEVICE

  [1] NVIDIA GeForce RTX 4090
      Provider: NVIDIA | Version: 32.0.15.8129

  [2] NVIDIA GeForce RTX 4080 Super
      Provider: NVIDIA | Version: 32.0.15.8129

  [3] AMD Radeon RX 7900 XTX
      Provider: AMD | Version: 24.10.1

Enter GPU number (1-3): 1
```

**Process Output Example:**

```
  [14:24:30] ~ ANALYZING GPU DRIVERS

  [14:24:30] > GPU: NVIDIA GeForce RTX 4090
  [14:24:30] > Provider: NVIDIA
  [14:24:30] > Version: 32.0.15.8129

  [14:24:30] > Finding INF file from registry...
  [14:24:31] + Found INF: oem123.inf
  [14:24:31] > Reading INF file...
  [14:24:31] > Parsing INF for file references...
  [14:24:32] + Found 247 file references in INF
  [14:24:32] > Locating files in system...
  [14:24:33] + Located 156 system files + 8 DriverStore folder(s)

  [14:24:33] ~ COPYING DRIVERS

  [14:24:33] > Copying 8 DriverStore folders...
  [14:24:34] + nv_dispi.inf_amd64_87654321 (1,245 files)
  [14:24:35] + nvapi_dispi.inf_amd64_12345678 (823 files)
  ...

  [14:24:40] > Copying 156 system files...
  [14:24:40] + nvapi64.dll
  [14:24:40] + nv4_mini.sys
  [14:24:40] + nvd3dum.dll
  ...

  [14:24:55] ~ DRIVER INJECTION COMPLETE

  [14:24:55] + Injected 156 files + 8 folders to MyGameVM
```

**Multi-GPU Support:**

When multiple GPUs are present, the script displays all available devices:

```powershell
# Host with 2 NVIDIA GPUs
$gpus = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq "Display" }

# Result:
# [1] NVIDIA GeForce RTX 4090       (32.0.15.8129)
# [2] NVIDIA GeForce RTX 4080 Super (32.0.15.8129)

# User selects which GPU's drivers to inject
```

**What Gets Copied:**

- All driver files referenced in the GPU INF file
- Entire DriverStore folders (not individual files from them)
- System library files (.dll, .sys, .exe, .cat, .inf)
- Binary resources (.bin, .vp, .cpa files)

**What Doesn't Get Copied:**

- Application-specific dependencies (must be installed separately in VM)
- CUDA runtime libraries (for compute workloads, install CUDA toolkit in VM)
- Game-specific libraries or redistributables

### Complete Setup

Orchestrates the full workflow: VM creation, GPU partition configuration, and driver injection preparation.

```powershell
PS> (Select "Complete Setup" from menu)
PS> (Select preset configuration)
PS> VM Name: MyGameVM
PS> ISO Path: C:\ISOs\Windows11Pro.iso
PS> GPU Allocation % (default: 50): 50
```

This combines Create New VM and Configure GPU Partition.

**Typical workflow after Complete Setup:**

```powershell
1. [Complete Setup] - Creates VM + partitions GPU
2. Open Hyper-V Manager - Start VM and install Windows OS
3. Complete Windows installation inside VM
4. Shutdown VM completely
5. [Inject GPU Drivers (Auto-Detect)] - Install drivers
6. Start VM - GPU drivers now loaded
7. Install games/applications - May require per-app DLL troubleshooting
```

### Update VM Drivers (Auto-Detect)

Synchronizes VM GPU drivers with host system. Useful after updating GPU drivers on host.

```powershell
PS> (Select "Update VM Drivers (Auto-Detect)" from menu)
PS> (Arrow keys to select VM)
PS> (Same driver detection and injection process as "Inject GPU Drivers")
```

Process is identical to "Inject GPU Drivers (Auto-Detect)" but performed on already-configured VMs.

### List VMs & GPU Info

Displays comprehensive inventory of all VMs and host GPU information with accurate VRAM detection using vendor-specific tools.

```powershell
PS> (Select "List VMs & GPU Info" from menu)

================================================================================
                         HYPER-V VIRTUAL MACHINES
================================================================================

  [14:25:00] > Gathering VM info...

  +--------------------------------------------------------------------------+
  |  VM: Gaming-VM
  |  State: Running | RAM: 16GB | CPU: 8 | Storage: 256GB | GPU: 50%
  +--------------------------------------------------------------------------+

  +--------------------------------------------------------------------------+
  |  VM: Dev-VM
  |  State: Off | RAM: 8GB | CPU: 4 | Storage: 128GB | GPU: None
  +--------------------------------------------------------------------------+

  +--------------------------------------------------------------------------+
  |  VM: ML-VM
  |  State: Running | RAM: 32GB | CPU: 12 | Storage: 512GB | GPU: 60%
  +--------------------------------------------------------------------------+

================================================================================
                          HOST GPU INFORMATION
================================================================================

  GPU: NVIDIA GeForce RTX 4090
  Driver Version: 32.0.15.8129
  Driver Date: 11/01/2024
  VRAM: 24.0 GB (nvidia-smi)
  Status: OK

  GPU: AMD Radeon RX 7900 XTX
  Driver Version: 24.10.1
  Driver Date: 10/15/2024
  VRAM: 24.0 GB (rocm-smi)
  Status: OK

  GPU: Intel Arc A770
  Driver Version: 31.0.101.5272
  Driver Date: 10/20/2024
  VRAM: 8.0 GB (registry)
  Status: OK
```

**VRAM Detection Methods:**

The script uses vendor-specific tools for accurate VRAM reporting:

- **NVIDIA:** `nvidia-smi --query-gpu=memory.total` (most accurate)
- **AMD:** `rocm-smi --showmeminfo` (when ROCm installed)
- **Intel Arc/iGPU:** Windows Registry `HardwareInformation.qxvram` (always available)
- **Fallback:** WMI `AdapterRAM` (unreliable for >4GB GPUs, marked as "WMI (unreliable)")

### Copy VM Apps to Downloads

Copies application zip files from host to VM's Downloads folder. Requires:

1. "VM Apps" folder in script directory
2. Zip files inside "VM Apps" folder
3. VM in powered-off state

```powershell
PS> (Create folder: ".\VM Apps\")
PS> (Place zip files in VM Apps folder)
PS> (Select "Copy VM Apps to Downloads" from menu)
PS> (Arrow keys to select target VM)

COPYING VM APPLICATIONS

  [14:25:30] > Target: Gaming-VM
  [14:25:31] > Found 3 app(s)
  [14:25:32] > Detecting user account...
  [14:25:33] > Copying apps...
  [14:25:33] + Sunshine.zip
  [14:25:34] + VB-Cable.zip
  [14:25:34] + VirtualAudio.zip

COPIED: 3/3 files

  [14:25:35] > Location: Users\Gaming\Downloads\VM Apps
```

Files are copied to: `C:\Users\[Username]\Downloads\VM Apps\`

## Known Limitations

### Application Compatibility and DLL Dependencies

The tool automates baseline driver installation but does not resolve per-application compatibility issues:

**Supported:**
- DirectX 9/10/11/12 applications
- Standard display driver rendering
- Basic GPU initialization and VRAM allocation

**Not Supported or Requires Manual Setup:**
- CUDA compute libraries (install CUDA toolkit inside VM)
- Application-specific dependencies and redistributables
- OpenGL rendering (translated through DirectX 12 - may have glitches)
- Vulkan API (no support in GPU-PV)
- DLSS and Frame Generation features

**Troubleshooting Application DLL Errors:**

If an application fails to run with a DLL error, manually copy the missing library:

```powershell
# On host system, locate the missing DLL
PS> Get-ChildItem C:\Windows\System32 -Filter "curand64.dll"

# Copy to VM's System32 (when VM is powered off, after driver injection)
PS> Copy-Item "C:\Windows\System32\curand64.dll" "C:\Temp\VMMount_12345\Windows\System32\"
```

### OpenGL Applications

GPU-PV translates OpenGL calls to DirectX 12. This causes:

- Performance degradation in OpenGL-heavy workloads
- Rendering glitches or crashes in certain OpenGL features
- Incompatibility with advanced OpenGL extensions

**Mitigation:** Use DirectX version of application if available. For DirectX games, GPU-PV provides near-native performance.

### Vulkan and Advanced Graphics Features

Not supported by GPU-PV architecture:

- Vulkan API rendering
- DLSS (Deep Learning Super Sampling)
- Frame Generation (RTX Super Resolution)
- Explicit GPU scheduling enhancements

## Workflow Examples

### Gaming VM Setup

```powershell
# Step 1: Create VM
PS> (Select "Create New VM")
PS> (Select Gaming preset)
PS> VM Name: GamingVM
PS> ISO Path: C:\ISOs\Windows11.iso

# Step 2: Install Windows inside VM
PS> (Open Hyper-V Manager, start GamingVM, install Windows)

# Step 3: Inject GPU drivers
PS> (Select "Inject GPU Drivers (Auto-Detect)")
PS> (Arrow keys to select GamingVM)
PS> (Select NVIDIA RTX 4090)

# Step 4: Configure GPU allocation
PS> (Select "Configure GPU Partition")
PS> (Select GamingVM)
PS> GPU Allocation: 50

# Result: Gaming VM with GPU-accelerated DirectX rendering
```

### Multi-GPU Load Balancing

```powershell
# Host with RTX 4090 + RTX 4080 Super

# Gaming-VM gets RTX 4090 at 50%
PS> (Create GamingVM, Inject RTX 4090 drivers, allocate 50%)

# Dev-VM gets RTX 4080 Super at 40%
PS> (Create DevVM, Inject RTX 4080 drivers, allocate 40%)

# Result: Both VMs accessing different GPUs simultaneously
```

### Development VM with Unreal Engine

```powershell
# Step 1: Complete Setup
PS> (Select "Complete Setup")
PS> (Select Development preset)
PS> GPU Allocation: 40

# Step 2: Install Windows + GPU drivers

# Step 3: Inside VM, download and install Unreal Engine

# GPU partitioning ensures GPU memory is reserved for rendering
# DirectX 11/12 rendering works with near-native performance
```

### Machine Learning VM with CUDA

```powershell
# Step 1: Complete Setup
PS> (Select "Complete Setup")
PS> (Select ML Training preset - 32GB RAM)
PS> GPU Allocation: 75

# Step 2: Install Windows + GPU drivers

# Step 3: Inside VM, install CUDA toolkit (not included with drivers)
PS> # Download from https://developer.nvidia.com/cuda-downloads
PS> # Install CUDA for access to compute libraries (curand64.dll, etc.)

# Step 4: Install PyTorch, TensorFlow, etc.
# Now CUDA compute operations are available for ML workloads
```

## Troubleshooting

### GPU Not Detected in VM

**Symptom:** Device Manager shows no GPU in VM after driver injection

**Cause:** Drivers not properly copied or Windows partition not detected

**Resolution:**

```powershell
# Verify VM has GPU partition configured
PS> Get-VMGpuPartitionAdapter -VMName GamingVM
PS> # Should output GPU partition details

# If no output, configure GPU partition
PS> (Select "Configure GPU Partition" from menu)

# Verify Windows installation
PS> # Connect to VM, open Device Manager
PS> # Check for "PCI Controller" with warning/error indicator
```

### Driver Injection Fails with "Windows Not Installed"

**Symptom:** Error during driver injection: "Windows directory not found"

**Cause:** VM disk does not have Windows installation yet

**Resolution:**

```powershell
# Create and start VM
PS> (Select "Create New VM" with ISO)

# Boot into Windows installation
PS> # Inside Hyper-V Manager, start VM and complete Windows Setup

# Shutdown VM
PS> # After Windows installation completes, shutdown the VM

# Now inject drivers
PS> (Select "Inject GPU Drivers (Auto-Detect)")
```

### Multiple GPUs Show in Selection Menu, Wrong One Selected

**Symptom:** Three GPUs appear in selection menu, but selected GPU not recognized

**Cause:** GPU driver information not properly registered in registry

**Resolution:**

```powershell
# Verify GPU driver installation
PS> nvidia-smi  # For NVIDIA GPUs
PS> Get-WmiObject Win32_VideoController | Select Name, DriverVersion

# Update GPU drivers through:
# - Device Manager (Update Driver)
# - Manufacturer's driver download page
# - AMD Radeon Software / NVIDIA GeForce Experience

# Reboot system

# Retry driver injection
```

### Insufficient Disk Space During Driver Copy

**Symptom:** Error during driver injection: "Not enough space"

**Cause:** VM virtual disk full

**Resolution:**

```powershell
# Expand VM virtual disk
PS> $vm = Get-VM MyVM
PS> $disk = Get-VHD -Path $vm.HardDrives[0].Path
PS> Resize-VirtualDisk -Path $disk.Path -SizeBytes 500GB

# Or delete unused files inside VM to free space
```

## PowerShell Examples

### Programmatic VM Creation

```powershell
# Create VM without UI
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

### Programmatic GPU Driver Injection

```powershell
# Inject drivers without menu selection
$selectedGPU = Select-GPUDevice  # Shows menu
$driverData = Get-DriverFiles -GPU $selectedGPU
# Drivers now extracted and ready to inject
```

### Query VM GPU Allocation

```powershell
# Check GPU allocation for all VMs
$vms = Get-VM

foreach ($vm in $vms) {
    $gpuAdapter = Get-VMGpuPartitionAdapter $vm.Name -ErrorAction SilentlyContinue
    
    if ($gpuAdapter) {
        $allocationPercent = [math]::Round(($gpuAdapter.MaxPartitionVRAM / 1000000000) * 100, 0)
        Write-Host "$($vm.Name): $allocationPercent% GPU"
    } else {
        Write-Host "$($vm.Name): No GPU partition"
    }
}
```

**Output:**
```
GamingVM: 50% GPU
Dev-VM: No GPU partition
ML-VM: 75% GPU
```

### List All Host GPUs with VRAM

```powershell
# Enumerate all GPUs with accurate VRAM detection
$gpus = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq "Display" }

foreach ($gpu in $gpus) {
    Write-Host "Name: $($gpu.DeviceName)"
    Write-Host "Driver: $($gpu.DriverVersion)"
    Write-Host "Provider: $($gpu.DriverProviderName)"
    
    # Try NVIDIA
    if ($gpu.DeviceName -like "*NVIDIA*") {
        $vram = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        if ($vram) { Write-Host "VRAM: $([int]$vram / 1024) GB (nvidia-smi)" }
    }
    Write-Host "---"
}
```

**Output:**
```
Name: NVIDIA GeForce RTX 4090
Driver: 32.0.15.8129
Provider: NVIDIA
VRAM: 24 GB (nvidia-smi)
---
Name: AMD Radeon RX 7900 XTX
Driver: 24.10.1
Provider: AMD
---
```

## Technical Details

### Virtual Disk Mounting Process

```powershell
# VHD mounting sequence
Mount-VHD -NoDriveLetter                    # Mount without drive letter
Update-Disk -DiskNumber $num                # Refresh partition info
Get-Partition -DiskNumber $num              # Enumerate partitions
Add-PartitionAccessPath                     # Mount to temporary folder
Test-Path "$mount\Windows"                  # Verify OS installation

# After operations
Remove-PartitionAccessPath                  # Unmount partition
Dismount-VHD -Path $vhd                    # Dismount VHD
Remove-Item $mount -Recurse -Force         # Clean temporary folder
```

### GPU Partition Value Calculation

```powershell
# For 50% GPU allocation
$percentage = 50
$maxValue = [int](($percentage / 100) * 1000000000)

# Calculation:
# (50 / 100) * 1,000,000,000 = 500,000,000

# Applied to all partition types (VRAM, Encode, Decode, Compute)
Set-VMGpuPartitionAdapter -VMName MyVM `
    -MaxPartitionVRAM 500000000 `
    -OptimalPartitionVRAM 499999999 `
    -MaxPartitionEncode 500000000 `
    -OptimalPartitionEncode 499999999
    # ... etc for Decode and Compute
```

### Memory-Mapped I/O Configuration

```powershell
# GPU access through memory mapping
Set-VM -VMName MyVM `
    -GuestControlledCacheTypes $true `        # Allow guest to control cache
    -LowMemoryMappedIoSpace 1GB `             # Low address space for I/O
    -HighMemoryMappedIoSpace 32GB             # High address space for GPU VRAM
```

This maps physical GPU memory into the guest VM's address space, enabling direct GPU communication.

## Advanced Configuration

### Custom VM Storage Path

By default, VMs are stored in `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`. To use a different path:

```powershell
# During VM creation, when prompted:
PS> Storage Path: D:\Hyper-V\VMs\MyVM.vhdx

# Or programmatically:
$config.Path = "D:\Hyper-V\VMs\"
$vmName = Initialize-VM -Config $config
```

### Changing GPU Allocation After VM Creation

```powershell
# Modify GPU partition percentage
$vmName = "GamingVM"
$newPercent = 75

# Stop VM if running
if ((Get-VM $vmName).State -ne "Off") {
    Stop-VM $vmName -Force
}

# Reconfigure GPU partition
Set-GPUPartition -VMName $vmName -Percentage $newPercent
```

### Viewing VM Configuration

```powershell
# Get all VM settings
$vm = Get-VM -Name "GamingVM"

# Display configuration
Write-Host "Name: $($vm.Name)"
Write-Host "State: $($vm.State)"
Write-Host "RAM: $([math]::Round($vm.MemoryAssigned / 1GB)) GB"
Write-Host "CPUs: $($vm.ProcessorCount)"

# Get GPU info
$gpu = Get-VMGpuPartitionAdapter -VMName "GamingVM" -ErrorAction SilentlyContinue
if ($gpu) {
    $percent = [math]::Round(($gpu.MaxPartitionVRAM / 1000000000) * 100)
    Write-Host "GPU: $percent%"
}
```

## Credits

Built on GPU-PV (GPU Paravirtualization) technology by Microsoft for Hyper-V and Windows Server. Driver detection and injection architecture supports universal GPU support through vendor-agnostic INF registry resolution and file discovery.

Current implementation thoroughly tested with NVIDIA GPUs (GeForce, RTX, and Quadro series). AMD Radeon and Intel Arc driver detection follows the same registry and INF parsing mechanisms and should function correctly with proper driver installation on host system.

## License

Provided as-is for personal and educational use. No warranty. Use at your own risk.

**Disclaimer:** GPU virtualization depends on compatible hardware and may not work with all GPU models or driver versions. Application compatibility varies - this tool automates initial driver setup but cannot prevent per-app compatibility issues or missing dependencies. Always backup important data before VM operations.

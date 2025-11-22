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

The script automatically requests administrator elevation if not already running with elevated privileges.

## User Interface and Workflows

### Main Menu

The application presents an interactive menu system with arrow key navigation:

```
  > MAIN MENU
  |  (Use UP/DOWN arrows, ENTER to select)
  |
  |     Create New VM
  |  >> Configure GPU Partition      [green highlight - currently selected]
  |     Inject GPU Drivers (Auto-Detect)
  |     Complete Setup (VM + GPU + Drivers)
  |     Update VM Drivers (Auto-Detect)
  |     List VMs & GPU Info
  |     Copy VM Apps to Downloads
  |     Exit
  |
  >==========================================================================
```

**Navigation:**
- **UP Arrow** - Move selection up (wraps to bottom)
- **DOWN Arrow** - Move selection down (wraps to top)
- **ENTER** - Confirm selection

### Logging Output

All operations produce timestamped, color-coded log messages:

| Symbol | Color | Level | Usage |
|--------|-------|-------|-------|
| `>` | Cyan | INFO | General operations |
| `+` | Green | SUCCESS | Completed successfully |
| `!` | Yellow | WARN | Non-fatal issues |
| `X` | Red | ERROR | Failures requiring attention |
| `~` | Magenta | HEADER | Section headers |

Example output:
```
  [14:23:45] > GPU: NVIDIA RTX 4090                                    [Cyan]
  [14:23:45] + Found INF: oem123.inf                                   [Green]
  [14:23:46] > Reading INF file...                                     [Cyan]
  [14:23:47] ! Could not find GPU in registry                          [Yellow]
  [14:23:48] X INF file not found: C:\Windows\INF\oem456.inf          [Red]
```

## Menu Options Reference

### 1. Create New VM

Launches VM creation wizard with preset or custom configuration. Creates a Generation 2 VM with UEFI firmware, Secure Boot, and TPM 2.0 support.

**Preset Selection:**

```
  > VM CONFIGURATION
  |  (Use UP/DOWN arrows, ENTER to select)
  |
  |     Gaming       | 16GB RAM, 8 CPU,  256GB Storage
  |  >> Development  | 8GB RAM,  4 CPU,  128GB Storage
  |     ML Training  | 32GB RAM, 12 CPU, 512GB Storage
  |     Custom Configuration
```

**User Input:**

```powershell
  VM Name (default: Dev-VM): MyGameVM
  ISO Path (Enter to skip): C:\ISOs\Windows11Pro.iso
```

**VM Configuration:**
- Memory: Static allocation (no dynamic memory)
- Generation: 2 (UEFI)
- Security: Secure Boot enabled, TPM 2.0 enabled
- Checkpoints: Disabled
- Boot order: DVD drive first, HDD second (allows Windows installation from ISO)

**Example Output:**

```
  > CREATING VIRTUAL MACHINE
  [14:24:00] > VM: MyGameVM | RAM: 16GB | CPU: 8 | Storage: 256GB
  [14:24:00] | Creating VM configuration...
  [14:24:02] + Creating VM configuration...
  [14:24:02] | Configuring processor and memory...
  [14:24:03] + Configuring processor and memory...
  [14:24:03] | Attaching DVD drive and setting boot order...
  [14:24:04] + Attaching DVD drive and setting boot order...
  [14:24:04] + Mounting ISO image...
  [14:24:05] + Virtual machine created successfully
```

### 2. Configure GPU Partition

Adds GPU partition adapter to a VM and allocates a percentage of GPU resources (1-100%).

**VM Selection:**

```
  +========================================================================+
  |  SELECT VIRTUAL MACHINE                                              |
  +========================================================================+

  [1] Gaming-VM | State: Off | RAM: 16GB | CPU: 8 | GPU: None
  [2] Dev-VM | State: Off | RAM: 8GB | CPU: 4 | GPU: 25%
  [3] ML-VM | State: Running | RAM: 32GB | CPU: 12 | GPU: 60%
  [4] < Cancel >
```

**User Input:**

```powershell
  GPU Allocation % (1-100): 50
```

**Example Output:**

```
  [14:25:00] ~ CONFIGURING GPU PARTITION
  [14:25:00] > VM: Gaming-VM
  [14:25:01] > Setting GPU partition to 50%
  [14:25:02] + GPU partition configured successfully
```

### 3. Inject GPU Drivers (Auto-Detect)

Automatically detects GPU drivers from host system and injects them into selected VM disk image. Requires VM to be powered off with Windows already installed.

**VM Selection:**

Same as Configure GPU Partition - select target VM from list.

**GPU Selection (Multi-GPU Systems):**

```
  > SELECT GPU DEVICE
  |
  |  [1] NVIDIA GeForce RTX 4090
  |      Provider: NVIDIA | Version: 32.0.15.8129
  |
  |  [2] NVIDIA GeForce RTX 4080 Super
  |      Provider: NVIDIA | Version: 32.0.15.8129
  |
  |  [3] AMD Radeon RX 7900 XTX
  |      Provider: AMD | Version: 24.10.1
  |
  |  Enter GPU number (1-3): 1
```

**Process Output:**

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

  [14:24:55] + Injected 156 files + 8 folders to Gaming-VM
```

**What Gets Copied:**
- All driver files referenced in GPU INF file
- Entire DriverStore folders (preserves driver package integrity)
- System library files (.dll, .sys, .exe, .cat, .inf, .bin, .vp, .cpa)

**What Doesn't Get Copied:**
- Application-specific dependencies (install separately in VM)
- CUDA runtime libraries (install CUDA toolkit inside VM for compute workloads)
- Game-specific or application-specific libraries

### 4. Complete Setup (VM + GPU + Drivers)

Orchestrates the full workflow: VM creation, GPU partition configuration, and driver injection preparation.

**Combined Input:**

```powershell
  VM Configuration: Gaming       | 16GB RAM, 8 CPU,  256GB Storage
  VM Name (default: Gaming-VM): MyGameVM
  ISO Path (Enter to skip): C:\ISOs\Windows11Pro.iso

  [VM creation process...]

  GPU Allocation % (1-100): 50
```

**Typical workflow after Complete Setup:**

```powershell
1. [Complete Setup] - Creates VM + partitions GPU
2. Open Hyper-V Manager - Start VM and install Windows OS
3. Complete Windows installation inside VM
4. Shutdown VM completely
5. [Inject GPU Drivers (Auto-Detect)] - Install drivers
6. Start VM - GPU drivers now loaded
7. Install games/applications
```

### 5. Update VM Drivers (Auto-Detect)

Synchronizes VM GPU drivers with host system. Useful after updating GPU drivers on host system. Process identical to "Inject GPU Drivers (Auto-Detect)".

**Example scenario:**

```powershell
# Host GPU drivers updated from 32.0.15 to 32.0.20
PS> (Select "Update VM Drivers (Auto-Detect)" from menu)
PS> (Select target VM)
PS> (Select GPU device)

[Driver injection process runs again with new drivers]
```

### 6. List VMs & GPU Info

Displays comprehensive inventory of all VMs and host GPU information with VRAM accurately detected using vendor-specific tools.

**Example Output:**

```
  ================================================================================
                           HYPER-V VIRTUAL MACHINES
  ================================================================================

  [14:25:00] > Gathering VM info...

  +----------------------------------------------------------------------+
  |  VM: Gaming-VM
  |  State: Running | RAM: 16GB | CPU: 8 | Storage: 256GB | GPU: 50%
  +----------------------------------------------------------------------+

  +----------------------------------------------------------------------+
  |  VM: Dev-VM
  |  State: Off | RAM: 8GB | CPU: 4 | Storage: 128GB | GPU: None
  +----------------------------------------------------------------------+

  +----------------------------------------------------------------------+
  |  VM: ML-VM
  |  State: Running | RAM: 32GB | CPU: 12 | Storage: 512GB | GPU: 60%
  +----------------------------------------------------------------------+

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
- **NVIDIA:** `nvidia-smi --query-gpu=memory.total` (most accurate)
- **AMD:** `rocm-smi --showmeminfo` (when ROCm installed)
- **Intel Arc/iGPU:** Windows Registry `HardwareInformation.qxvram` (always available)
- **Fallback:** WMI `AdapterRAM` (unreliable for >4GB GPUs)

### 7. Copy VM Apps to Downloads

Copies application zip files from "VM Apps" folder (in script directory) to VM's Downloads folder. Requires VM to be powered off with Windows installed.

**Setup Required:**

```
Script Directory\
├── Unified-VM-Manager.ps1
└── VM Apps\
    ├── Sunshine.zip
    ├── VB-Cable.zip
    └── VirtualAudio.zip
```

**VM Selection:**

Same as other VM operations - select target VM from list.

**Example Output:**

```
  +========================================================================+
  |  COPYING VM APPLICATIONS                                             |
  +========================================================================+

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

**Files Copied To:** `C:\Users\[Username]\Downloads\VM Apps\`

## Known Limitations

### Application Compatibility and DLL Dependencies

The tool automates baseline driver installation but does not resolve per-application compatibility issues.

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
Select "Create New VM" from main menu
Select "Gaming" preset
VM Name: GamingVM
ISO Path: C:\ISOs\Windows11.iso

# Step 2: Install Windows inside VM
Open Hyper-V Manager, start GamingVM
Complete Windows installation

# Step 3: Inject GPU drivers
Select "Inject GPU Drivers (Auto-Detect)"
Select GamingVM from list
Select NVIDIA RTX 4090
[Driver injection completes]

# Step 4: Configure GPU allocation
Select "Configure GPU Partition"
Select GamingVM
GPU Allocation: 50

# Result: Gaming VM with GPU-accelerated DirectX rendering
```

### Multi-GPU Load Balancing

```powershell
# Host with RTX 4090 + RTX 4080 Super

# Gaming-VM gets RTX 4090 at 50%
Create Gaming-VM
Inject RTX 4090 drivers
Allocate 50% GPU

# Dev-VM gets RTX 4080 Super at 40%
Create Dev-VM
Inject RTX 4080 drivers
Allocate 40% GPU

# Result: Both VMs accessing different GPUs simultaneously
```

### Development VM with Unreal Engine

```powershell
# Step 1: Complete Setup
Select "Complete Setup"
Select "Development" preset
GPU Allocation: 40

# Step 2: Install Windows + GPU drivers
[Complete setup handles VM creation + GPU partitioning]
Install Windows in Hyper-V Manager
Inject GPU Drivers (Auto-Detect)

# Step 3: Inside VM, download and install Unreal Engine
# GPU partitioning ensures GPU memory is reserved for rendering
# DirectX 11/12 rendering works with near-native performance
```

### Machine Learning VM with CUDA

```powershell
# Step 1: Complete Setup
Select "Complete Setup"
Select "ML Training" preset (32GB RAM)
GPU Allocation: 75

# Step 2: Install Windows + GPU drivers
[Complete setup handles VM creation + GPU partitioning]
Install Windows in Hyper-V Manager
Inject GPU Drivers (Auto-Detect)

# Step 3: Inside VM, install CUDA toolkit (not included with drivers)
Download from https://developer.nvidia.com/cuda-downloads
Install CUDA for access to compute libraries

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
# Should output GPU partition details

# If no output, configure GPU partition
Select "Configure GPU Partition" from menu

# Verify Windows installation
# Connect to VM, open Device Manager
# Check for "PCI Controller" with warning/error indicator
```

### Driver Injection Fails with "Windows Not Installed"

**Symptom:** Error during driver injection: "Windows directory not found"

**Cause:** VM disk does not have Windows installation yet

**Resolution:**

```powershell
# Step 1: Create and start VM
Select "Create New VM" with ISO

# Step 2: Boot into Windows installation
# Inside Hyper-V Manager, start VM and complete Windows Setup

# Step 3: Shutdown VM
# After Windows installation completes, shutdown the VM

# Step 4: Now inject drivers
Select "Inject GPU Drivers (Auto-Detect)"
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
PS> Restart-Computer

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

### Query VM GPU Allocation

```powershell
# Check GPU allocation for all VMs
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

## Technical Architecture

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

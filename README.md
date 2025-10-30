# 🎮 GPU Virtualization Manager v3.0

**Unified Hyper-V Manager with Automated GPU Partition Support**

A streamlined PowerShell tool for creating and managing Hyper-V virtual machines with integrated GPU partitioning and NVIDIA driver injection. This solution consolidates VM creation, GPU resource allocation, and driver management into a single, efficient terminal interface with an intuitive arrow-key menu system.

⚠️ **Important:** This tool automates the initial setup (VM creation, GPU partition configuration, baseline driver injection). Application-specific compatibility issues and DLL troubleshooting remain manual tasks - see "Known Limitations" below.

---

## ✨ Key Features

- **🚀 Interactive Navigation** - Arrow-key based menu system for intuitive control
- **🎯 Quick Presets** - One-selection VM configurations for Gaming, Development, and Machine Learning
- **💾 Dynamic GPU Partitioning** - Configurable GPU allocation from 1-100% per VM
- **🔄 Automated Driver Injection** - Direct NVIDIA driver installation into VM disk images without manual intervention
- **🖥️ Modern Terminal UI** - Clean, color-coded interface with real-time progress indicators
- **⚙️ Complete Automation** - VM creation and driver injection in minutes
- **🔧 Intelligent Detection** - Smart partition discovery, driver location, and error handling
- **📊 Detailed Dashboard** - Real-time VM status with GPU VRAM reporting via nvidia-smi
- **📡 VM Apps Integration** - Automatic copying of tools to VM Downloads folder for easy setup

---

## 🚨 Known Limitations & Issues

### ⚠️ Critical: Application Compatibility (DLL Requirements)

**What Works:**
- Basic DirectX 9/10/11/12 games and applications
- Standard NVIDIA display drivers and partition detection
- VM-to-GPU communication for graphics rendering

**What Doesn't Work / Requires Manual Setup:**
- **Missing Application DLLs** - The script copies baseline NVIDIA drivers (`nv_dispi.inf_amd64` + `nv*.dll`/`nv*.exe`), but many applications require additional libraries not included in the basic driver set:
  - CUDA runtime libraries (curand64.dll, cufft64.dll, etc.) - needed for GPU compute, ML frameworks
  - OpenCL libraries - required by some professional software
  - Application-specific vendor libraries
  - **This is the biggest source of "app won't run" issues after driver injection**

**Manual Workaround:**
If an application fails to run in the VM after driver injection, you'll need to manually identify and copy the missing DLLs from the host `C:\Windows\System32` to the VM's `C:\Windows\System32`. For CUDA-dependent apps, you may need to download the CUDA toolkit separately inside the VM.

---

### ⚠️ OpenGL Applications - DirectX Translation Layer

**Issue:** GPU-PV translates OpenGL calls to DirectX 12 through a compatibility layer. This causes:
- **Performance degradation** in OpenGL-heavy applications
- **Rendering glitches or crashes** in certain OpenGL features
- **Incompatibility** with advanced OpenGL extensions
- **No support** for Vulkan, DLSS, or Frame Generation

**DirectX Support:** ✅ Fully supported (DX9, DX10, DX11, DX12)
**OpenGL Support:** ⚠️ Translated through DX12 (use with caution)
**Vulkan Support:** ❌ Not supported
**DLSS/Frame Gen:** ❌ Not supported

**Recommendation:** If your primary application uses OpenGL, GPU-PV may not be the best solution. Consider GPU passthrough or native gaming on the host instead.

---

### ⚠️ GPU Support - NVIDIA Only

**Supported:** ✅ NVIDIA GeForce (GTX 1060 or better, 30/40/50 series recommended)
**AMD Support:** ❌ Not tested (driver paths are different)
**Intel Arc:** ❌ Not tested

The tool scans for NVIDIA drivers specifically. AMD and Intel GPU support would require different driver paths and has not been validated.

---

### ⚠️ Manual Installation Steps Still Required

**What's Automated:**
- VM creation
- GPU partition configuration
- Baseline driver injection

**What You Still Need to Do:**
1. Install Windows manually in the VM (no unattended setup yet)
2. Download and install application-specific dependencies
3. Configure VNC/RDP for remote access
4. Install games/software inside the VM
5. Troubleshoot app-specific DLL issues
6. Per-application tuning and configuration

**Estimated Time:** 30-45 minutes from VM creation to playable setup (this tool saves ~20 minutes of driver setup)

---

## 🔧 System Requirements

### Minimum Requirements
| Component | Specification |
|-----------|--------------|
| **Operating System** | Windows 10 Pro (20H1+) or Windows 11 Pro |
| **RAM** | 16GB (8GB host + 8GB VM minimum) |
| **CPU** | 6 cores (4 for VM, 2 for host) |
| **GPU** | NVIDIA GTX 1060 6GB or better |
| **Storage** | 128GB available SSD space |
| **Virtualization** | Hyper-V enabled, VT-x/AMD-V in BIOS |

### Recommended Setup
| Component | Specification |
|-----------|--------------|
| **Operating System** | Windows 11 Pro (latest build) |
| **RAM** | 32GB+ (16GB+ per VM) |
| **CPU** | 8+ cores (Ryzen 5 5600X / Intel i5-12400+) |
| **GPU** | NVIDIA RTX 3060+ (12GB+ VRAM) |
| **Storage** | 256GB+ NVMe SSD |

---

## 🚀 Quick Start Guide

### Step 1: Enable Hyper-V

Open PowerShell as Administrator and run:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All
```

**Note:** Restart required after enabling Hyper-V.

### Step 2: Verify NVIDIA Drivers

Ensure NVIDIA GPU drivers are installed on the host:

```powershell
nvidia-smi
```

You should see your GPU model, driver version, and VRAM details.

### Step 3: Run the Script

```powershell
# Allow script execution (one-time setup)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run the manager (auto-elevates to Administrator if needed)
.\Unified-VM-Manager.ps1
```

---

## 🎮 Navigation Guide

### Menu Navigation

The tool uses an **arrow-key navigation system** for intuitive control:

**Controls:**
- **↑ Up Arrow** - Move selection up
- **↓ Down Arrow** - Move selection down
- **Enter** - Confirm selection

**Visual Indicators:**
- **>>** appears next to the currently selected option
- Selected items are highlighted in **green**
- Menu items cycle continuously (going up from the first item selects the last)

**Example Menu:**
```
  |
  |  (Use UP/DOWN arrows to navigate, ENTER to select)
  |
  |     Create New VM
  |  >> Configure GPU Partition
  |     Inject GPU Drivers
  |     Complete Setup (VM + GPU + Drivers)
  |     Update VM Drivers
  |     List VMs & GPU Info
  |     Copy VM Apps to Downloads
  |     Exit
```

---

## 📋 Menu Options Explained

### **Create New VM**
Creates a basic Hyper-V virtual machine with optimized settings using an arrow-key preset selector.

**What it does:**
- Displays arrow-key navigable preset menu
- Creates Generation 2 VM with UEFI support
- Configures static RAM allocation (no dynamic memory)
- Sets up TPM 2.0 and Secure Boot for Windows 11
- Disables checkpoints and integration services
- Attaches ISO if provided
- Sets boot order (DVD → HDD)

**Presets:**
```
  |     Gaming       | 16GB RAM, 8 CPU, 256GB Storage
  |  >> Development  | 8GB RAM, 4 CPU, 128GB Storage
  |     ML Training  | 32GB RAM, 12 CPU, 512GB Storage
  |     Custom Configuration
```

**Navigation:**
- Use **UP/DOWN** arrows to highlight desired preset
- Press **ENTER** to select
- Follow prompts for VM name and ISO path

---

### **Configure GPU Partition**
Adds GPU partitioning to an existing VM.

**What it does:**
- Prompts for VM name (manual input)
- Requests GPU allocation percentage (1-100%)
- Auto-shuts down VM if running
- Removes old GPU partition adapters
- Calculates optimal partition values (VRAM, Encode, Decode, Compute)
- Configures memory-mapped I/O space (1GB low, 32GB high)
- Enables guest-controlled cache types

**Partition Formula:**
```
MaxValue = (Percentage / 100) × 1,000,000,000
OptimalValue = MaxValue - 1
MinValue = 1
```

---

### **Inject GPU Drivers**
Installs NVIDIA drivers directly into VM disk image.

**What it does:**
- Ensures VM is powered off
- Scans host for NVIDIA driver repositories
- Mounts VM virtual hard disk
- Detects Windows partition (10GB+ size)
- Verifies Windows installation exists
- Removes old NVIDIA drivers from VM
- Copies driver repositories (nv_dispi.inf_amd64*)
- Copies system files (nv*.dll, nv*.exe)
- Safe cleanup and disk unmount

**What it DOESN'T do:**
- Copy application-specific DLL dependencies
- Install CUDA runtime (if needed for compute tasks)
- Install VNC/RDP software
- Configure remote access

**⚠️ Important:** Windows must be installed in the VM before using this option.

---

### **Complete Setup (Recommended)**
Automated workflow combining VM creation and GPU partition configuration.

**What it does:**
1. Launches arrow-key preset selector
2. Creates VM with chosen configuration
3. Prompts for GPU allocation percentage
4. Configures GPU partition
5. Prepares VM for OS installation

**Interactive Flow:**
```
Step 1: Navigate presets with arrows → ENTER
Step 2: Enter VM name (or press ENTER for default)
Step 3: Enter ISO path (or press ENTER to skip)
Step 4: Enter GPU allocation percentage
```

**Next Steps After:**
1. Start the VM
2. Install Windows from attached ISO
3. Complete Windows setup
4. Shut down VM
5. Navigate to **Inject GPU Drivers**
6. **Manually install apps and troubleshoot DLL issues as needed**

---

### **Update VM Drivers**
Synchronizes VM GPU drivers with host system.

**What it does:**
- Same process as **Inject GPU Drivers**
- Overwrites existing drivers with latest from host
- Essential after host GPU driver updates
- Maintains driver version compatibility

**Use this when:**
- You updated NVIDIA drivers on the host
- VM has driver issues or outdated drivers
- After Windows updates that affect GPU drivers

---

### **List VMs & GPU Info**
System dashboard showing detailed VM and GPU information.

**Displays:**

**VM Inventory Table:**
```
  +----------------------------------------------------------------------------------------+
  | Name            | State       | RAM    | CPUs | Threads | Storage | GPU       |
  +----------------------------------------------------------------------------------------+
  | Gaming-VM       | Running     | 16GB   | 8    | 16      | 256GB   | 50%       |
  | Dev-VM          | Off         | 8GB    | 4    | 8       | 128GB   | 25%       |
  +----------------------------------------------------------------------------------------+
```

**GPU Information:**
- Host GPU model
- Driver version
- Accurate VRAM (via nvidia-smi, falls back to WMI)
- Detection status

**Legend:**
- RAM = Memory Assigned
- CPUs = CPU Core Count
- Threads = Logical Processors
- Storage = Virtual Disk Size
- GPU = GPU Allocation %

---

### **Copy VM Apps to Downloads**
Copies application zip files from host to VM's Downloads folder.

**What it does:**
- Reads zip files from `VM Apps` folder in script directory
- Mounts VM virtual hard disk
- Detects primary user profile
- Creates `VM Apps` subfolder in Downloads
- Copies all zip files to VM

**Setup Required:**
1. Create folder named `VM Apps` in same directory as script
2. Place application zip files in this folder (e.g., Sunshine.zip, VB-Cable.zip)
3. Navigate to this menu option
4. Enter VM name

**Files are copied to:**
```
C:\Users\[Username]\Downloads\VM Apps\
```

**Included Tools (Examples):**
| Tool | Purpose |
|------|---------|
| **Sunshine** | GPU-accelerated desktop streaming server compatible with Moonlight |
| **VB-Cable** | Virtual audio cable driver for routing host audio to VM |
| **Virtual Display Driver** | Enables headless display output for remote sessions |

**When to Use:**
- After driver injection and Windows installation are complete
- Before configuring streaming inside the VM
- Ideal for remote gaming or development environments

---

### **Exit**
Closes the GPU Virtualization Manager.

---

## 🛠️ Complete Workflow Example

### Scenario: Creating a Gaming VM

**Step 1 - Complete Setup**
```
1. Launch script → Navigate to "Complete Setup"
2. Arrow keys → Select "Gaming | 16GB RAM, 8 CPU, 256GB Storage"
3. Press ENTER
4. VM Name: [Press ENTER for default "Gaming-VM"]
5. ISO Path: C:\ISOs\Windows11.iso
6. GPU Allocation: 50
```

**Step 2 - Install Windows**
1. Open Hyper-V Manager
2. Right-click "Gaming-VM" → Connect
3. Start VM and install Windows 11
4. Complete Windows setup (username, network, etc.)
5. Shut down VM completely

**Step 3 - Inject Drivers**
```
1. Navigate to "Inject GPU Drivers"
2. Press ENTER
3. VM Name: Gaming-VM
4. Wait for completion
```

**Step 4 - Copy VM Apps (Optional)**
```
1. Create "VM Apps" folder with zip files
2. Navigate to "Copy VM Apps to Downloads"
3. Press ENTER
4. VM Name: Gaming-VM
```

**Step 5 - Configure Guest OS** (Inside VM)
1. Start VM and log in
2. Check Device Manager → Display Adapters
3. Should see "Microsoft Hyper-V GPU Partition Adapter"
4. Drivers auto-load from HostDriverStore
5. Extract and install tools from Downloads\VM Apps
6. Disable Hyper-V display adapter in Device Manager
7. **Troubleshoot app-specific DLL issues as they arise**
8. Install games and test

---

## 🔍 Technical Architecture

### VM Configuration (Automated)

```powershell
# Memory
Set-VMMemory -DynamicMemoryEnabled $false

# Processor
Set-VMProcessor -Count <user-specified>

# Checkpoints
Set-VM -CheckpointType Disabled -AutomaticCheckpointsEnabled $false

# Automatic Actions
Set-VM -AutomaticStopAction ShutDown -AutomaticStartAction Nothing

# Firmware
Set-VMFirmware -EnableSecureBoot On -BootOrder $dvd, $hdd

# TPM
Set-VMKeyProtector -NewLocalKeyProtector
Enable-VMTPM

# Integration Services
Disable-VMIntegrationService -Name "Guest Service Interface"
Disable-VMIntegrationService -Name "VSS"

# Enhanced Session Mode (Host-level)
Set-VMHost -EnableEnhancedSessionMode $false
```

### GPU Partition Configuration

```powershell
# Add GPU adapter
Add-VMGpuPartitionAdapter -VMName <name>

# Configure partition values
Set-VMGpuPartitionAdapter `
    -MinPartitionVRAM 1 `
    -MaxPartitionVRAM <calculated> `
    -OptimalPartitionVRAM <calculated-1> `
    -MinPartitionEncode 1 `
    -MaxPartitionEncode <calculated> `
    -OptimalPartitionEncode <calculated-1> `
    -MinPartitionDecode 1 `
    -MaxPartitionDecode <calculated> `
    -OptimalPartitionDecode <calculated-1> `
    -MinPartitionCompute 1 `
    -MaxPartitionCompute <calculated> `
    -OptimalPartitionCompute <calculated-1>

# Memory-mapped I/O
Set-VM -GuestControlledCacheTypes $true `
       -LowMemoryMappedIoSpace 1GB `
       -HighMemoryMappedIoSpace 32GB
```

### Driver Injection Process

**Host Driver Locations:**
```
C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_*
C:\Windows\System32\nv*.dll
C:\Windows\System32\nv*.exe
```

**What Gets Copied:**
- ✅ NVIDIA display driver repo (nv_dispi.inf_amd64*)
- ✅ Basic NVIDIA system DLLs (nv*.dll, nv*.exe)
- ❌ CUDA runtime libraries
- ❌ OpenCL libraries
- ❌ Application-specific dependencies

**VM Injection Targets:**
```
<MountPoint>\Windows\System32\HostDriverStore\FileRepository\
<MountPoint>\Windows\System32\
```

**Safe Mounting:**
1. Mount VHD without drive letter
2. Update disk information
3. Find partition > 10GB (Windows partition)
4. Mount to temporary path (C:\Temp\VMMount_<random>)
5. Copy drivers
6. Remove partition access path
7. Dismount VHD
8. Delete temporary mount directory

---

## 🎨 UI Design Elements

### Color-Coded Logging

The tool provides real-time feedback with color-coded logging:

| Level | Icon | Color | Purpose |
|-------|------|-------|---------|
| **INFO** | > | Cyan | General information and progress |
| **SUCCESS** | + | Green | Successful operations |
| **WARN** | ! | Yellow | Warnings and important notices |
| **ERROR** | X | Red | Errors requiring attention |
| **HEADER** | ~ | Magenta | Section headers and major steps |
| **DEBUG** | # | Dark Cyan | Debug information |

### Progress Indicators

**Loading Spinner:**
```
  | Creating VM configuration...
  / Configuring processor and memory...
  - Applying security settings...
  \ Finalizing VM setup...
  + Complete!
```

**Section Headers:**
```
  +============================================================================+
  |  GPU PARTITION CONFIGURATION                                               |
  +============================================================================+
```

**Section Dividers:**
```
  +----------------------------------------------------------------------------+
  |  VM CREATED SUCCESSFULLY                                                   |
  +----------------------------------------------------------------------------+
```

---

## 🚀 Advanced Usage

### Multiple VMs with GPU Access

**Scenario:** 2 VMs on RTX 4090

```
VM 1: Gaming-VM
  → Navigate to "Configure GPU Partition"
  → Enter VM Name: Gaming-VM
  → GPU Allocation: 40

VM 2: Dev-VM
  → Navigate to "Configure GPU Partition"
  → Enter VM Name: Dev-VM
  → GPU Allocation: 40

Remaining 20% for host
```

**Result:** Both VMs have GPU access simultaneously. Combined load shouldn't exceed ~80% to avoid host instability.

---

### Custom Storage Paths

By default, VHDs are stored in:
```
C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\
```

**To use custom path:**
- Script prompts during VM creation
- Enter full path: `D:\Hyper-V\VMs\`
- Ensure drive has sufficient space

---

### Automated ISO Mounting

During VM creation, when prompted for ISO:
```
ISO Path: C:\ISOs\Windows11.iso
```

Script automatically:
- Adds DVD drive to VM
- Mounts ISO
- Sets boot order (DVD before HDD)

To skip ISO: Press Enter when prompted.

---

### Manual GPU Tuning

Start conservative and increase:
```
Initial test: 25%
Light gaming: 35-40%
Standard gaming: 50%
Heavy workload: 60-70%
Maximum performance: 75-90%
```

Monitor host system stability at each level.

---

## 📊 Application Compatibility Guide

### DirectX Games (✅ Well Supported)
- Most modern games using DirectX 11/12
- Good performance, few compatibility issues
- **Examples:** Call of Duty, Fortnite, Valorant, Minecraft (DX mode)

### OpenGL Applications (⚠️ Compatibility Layer)
- Runs through DX12 translation
- **May experience:** Glitches, performance drops, crashes
- **Examples:** Blender (OpenGL mode), older games, some professional CAD software
- **Recommendation:** Use DirectX version if available

### CUDA/GPU Compute (⚠️ Requires Manual Setup)
- Basic compute support through GPU partition
- **Requires:** Manual installation of CUDA toolkit inside VM
- **Examples:** TensorFlow, PyTorch, CuPy
- **Note:** Must copy CUDA runtime DLLs manually

### Vulkan Applications (❌ Not Supported)
- GPU-PV does not support Vulkan
- Consider alternative virtualization solutions

---

## 🎮 Use Cases

### Gaming VM ✅
- DirectX games work well
- 50-60% GPU allocation for good performance
- Add VNC for streaming or remote play
- **Best Games:** Modern AAA titles using DirectX

### Development VM ✅
- Unity/Unreal development (GPU accelerated)
- GPU-accelerated testing
- Isolated development environments
- **Caveat:** OpenGL-heavy workflows may struggle

### Machine Learning VM ⚠️
- CUDA support works but requires manual setup
- Good for training workloads
- **Note:** Must install CUDA toolkit manually inside VM
- **Caveat:** TensorFlow/PyTorch need dependency troubleshooting

### Content Creation ⚠️
- DaVinci Resolve (CUDA rendering) - manual CUDA setup required
- Blender (OpenGL issue) - use Cycles with CUDA or Eevee
- Photo editing generally works
- **Caveat:** Check application's rendering engine compatibility

---

## 🔐 Security Considerations

### VM Isolation
- VMs are isolated from host by Hyper-V hypervisor
- Network traffic can be monitored via virtual switches
- File sharing requires explicit configuration

### Driver Access
- Host drivers copied to VM (read-only access)
- VM cannot modify host driver files
- HostDriverStore directory secured by Windows

### Administrator Rights
- Script requires admin for Hyper-V operations
- Auto-elevation prompts for UAC confirmation
- All operations logged with timestamps

---

## ❓ FAQ

**Q: How do I navigate the menu?**
A: Use UP/DOWN arrow keys to move between options. The selected option is highlighted with ">>" in green. Press ENTER to confirm your selection.

**Q: Why did my app crash after driver injection?**
A: Missing application-specific DLLs. Check `Event Viewer > Windows Logs > Application` for DLL errors. Manually copy the missing DLL from host `C:\Windows\System32` to VM `C:\Windows\System32`.

**Q: OpenGL games are laggy/broken. What do I do?**
A: GPU-PV translates OpenGL to DirectX 12, which causes performance issues. If a DirectX version exists, use that instead. Otherwise, consider GPU passthrough.

**Q: Can I use AMD GPUs?**
A: Not tested. The driver paths are different for AMD. Community contributions welcome on GitHub.

**Q: How do I reduce setup time?**
A: Use the "Complete Setup" option and follow the preset configurations. This automates VM creation and GPU partition in one workflow.

**Q: Can I run multiple VMs simultaneously with GPU access?**
A: Yes, allocate GPU percentages totaling <80%. More than 80% combined load may cause instability.

**Q: How do I copy apps to my VM?**
A: Create a folder named "VM Apps" in the script directory, place your zip files there, then use the "Copy VM Apps to Downloads" option.

**Q: Can I change preset values after selection?**
A: No, but you can select "Custom Configuration" from the preset menu to specify exact values.

---

## 🙏 Credits & Acknowledgments

Built upon the foundation of GPU-P (GPU Paravirtualization) technology developed by Microsoft for Windows Server and Hyper-V. This tool consolidates community knowledge and best practices into an accessible, automated solution with modern arrow-key navigation.

**Special thanks to:**
- Microsoft Hyper-V team for GPU-P feature development
- NVIDIA for driver support
- r/VFIO and r/HyperV communities for shared knowledge
- Early testers and contributors for identifying DLL and OpenGL issues
- UI/UX inspiration from modern terminal applications

---

## 📜 License

This tool is provided as-is for educational and personal use. No warranty is provided. Use at your own risk.

**Disclaimer:** GPU virtualization requires compatible hardware and may not work with all GPU models or driver versions. Application compatibility varies - this tool automates the initial setup but cannot prevent per-app compatibility issues. Always backup important data before creating VMs.

---

**🎮 Happy Virtualizing! 🚀**

*Built for power users, streamlined for everyone.*

*Saves you setup time. Leaves app troubleshooting to you.*

*Navigate with arrows. Create with confidence.*

---

**Latest Version:** v3.0 MODERN
**Last Updated:** October 2025
**Compatibility:** Windows 10/11 Pro, PowerShell 5.1+, NVIDIA GPUs only
**Supports:** DirectX 9/10/11/12 ✅ | OpenGL (via DX12 translation) ⚠️ | Vulkan ❌ | DLSS/Frame Gen ❌
**Navigation:** Arrow Keys (UP/DOWN) + ENTER

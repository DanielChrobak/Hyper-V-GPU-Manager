# 🎮 GPU Virtualization Manager v3.0

**Unified Hyper-V Manager with Automated GPU Partition Support**

A streamlined PowerShell tool for creating and managing Hyper-V virtual machines with integrated GPU partitioning and NVIDIA driver injection. This solution consolidates VM creation, GPU resource allocation, and driver management into a single, efficient terminal interface - democratizing GPU virtualization beyond enterprise-exclusive solutions.

---

## ✨ Key Features

- **🚀 One-Click VM Creation** - Preset configurations for Gaming, Development, and Machine Learning
- **🎯 Dynamic GPU Partitioning** - Configurable GPU allocation from 1-100% per VM
- **💾 Automated Driver Injection** - Direct NVIDIA driver installation into VM disk images without manual intervention
- **🔄 Driver Synchronization** - Keep VM drivers aligned with host GPU driver versions
- **🖥️ Modern Terminal UI** - Clean menu system with color-coded logging and timestamps
- **⚙️ Complete Automation** - From VM creation to driver installation in minutes, not hours
- **🔧 Intelligent Detection** - Smart partition discovery, driver location, and error handling
- **📊 System Dashboard** - Real-time VM status and accurate GPU VRAM reporting via nvidia-smi

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

## 📋 Menu Options Explained

### **[1] Create New VM**
Creates a basic Hyper-V virtual machine with optimized settings.

**What it does:**
- Prompts for VM configuration (3 presets + custom option)
- Creates Generation 2 VM with UEFI support
- Configures static RAM allocation (no dynamic memory)
- Sets up TPM 2.0 and Secure Boot for Windows 11
- Disables checkpoints and integration services
- Attaches ISO if provided
- Sets boot order (DVD → HDD)

**Presets:**
- **Gaming VM**: 16GB RAM, 8 CPU, 256GB storage
- **Dev VM**: 8GB RAM, 4 CPU, 128GB storage  
- **ML VM**: 32GB RAM, 12 CPU, 512GB storage
- **Custom**: Specify your own values

### **[2] Configure GPU Partition**
Adds GPU partitioning to an existing VM.

**What it does:**
- Selects VM from existing Hyper-V machines
- Prompts for GPU allocation percentage (1-100%)
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

### **[3] Inject GPU Drivers**
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

**⚠️ Important:** Windows must be installed in the VM before using this option.

### **[4] Complete Setup (Recommended)**
Automated workflow combining VM creation and GPU partition configuration.

**What it does:**
1. Creates VM with your chosen preset/custom config
2. Configures GPU partition with specified percentage
3. Prepares VM for OS installation

**Next Steps After:**
1. Start the VM
2. Install Windows from attached ISO
3. Complete Windows setup
4. Shut down VM
5. Use Option [3] to inject drivers

### **[5] Update VM Drivers**
Synchronizes VM GPU drivers with host system.

**What it does:**
- Same process as Option [3]
- Overwrites existing drivers with latest from host
- Essential after host GPU driver updates
- Maintains driver version compatibility

**Use this when:**
- You updated NVIDIA drivers on the host
- VM has driver issues or outdated drivers
- After Windows updates that affect GPU drivers

### **[6] List VMs & GPU Info**
System dashboard showing VM status and GPU information.

**Displays:**
- All Hyper-V VMs (Name, State, CPU Usage, RAM, GPU Enabled)
- Host GPU model
- Driver version
- Accurate VRAM (via nvidia-smi, falls back to WMI)

---

## 🛠️ Complete Workflow Example

### Scenario: Creating a Gaming VM

**Step 1 - Complete Setup**
```
Select option: 4
Select preset: 1 (Gaming)
VM Name: Gaming-VM (press Enter for default)
ISO Path: C:\ISOs\Windows11.iso
GPU Allocation: 50
```

**Step 2 - Install Windows**
1. Open Hyper-V Manager
2. Right-click "Gaming-VM" → Connect
3. Start VM and install Windows 11
4. Complete Windows setup (username, network, etc.)
5. Shut down VM completely

**Step 3 - Inject Drivers**
```
Select option: 3
VM Name: Gaming-VM
```

**Step 4 - Configure Guest OS** (Inside VM)
1. Start VM and log in
2. Check Device Manager → Display Adapters
3. Should see "Microsoft Hyper-V GPU Partition Adapter"
4. Drivers auto-load from HostDriverStore
5. Install VNC/RDP for remote access
6. Install VB-Cable for audio redirection
7. Disable Hyper-V display adapter in Device Manager
8. Install games and enjoy!

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

## 🎨 Logging System

The tool provides real-time feedback with color-coded logging:

| Level | Icon | Color | Purpose |
|-------|------|-------|---------|
| **INFO** | [i] | Cyan | General information and progress |
| **SUCCESS** | [+] | Green | Successful operations |
| **WARN** | [!] | Yellow | Warnings and important notices |
| **ERROR** | [X] | Red | Errors requiring attention |
| **HEADER** | [>] | Magenta | Section headers and major steps |

**Example Output:**
```
[20:15:42] [>] Initializing VM: Gaming-VM
[20:15:43] [+] VM created: Gaming-VM | RAM: 16GB | CPU: 8 | Storage: 256GB
[20:15:44] [+] Boot order configured: DVD first
[20:15:44] [+] ISO attached
[20:15:45] [>] GPU configured: 50% allocated to Gaming-VM
```

---

## 🧪 Troubleshooting

### Error: "WINDOWS IS NOT INSTALLED ON THIS VM"

**Cause:** Driver injection attempted before OS installation.

**Solution:**
1. Start the VM
2. Install Windows from ISO
3. Complete setup and shut down VM
4. Run Option [3] again

---

### Error: "VM must be off"

**Cause:** VM is running or in saved state.

**Solution:**
- Script auto-shuts down VMs, but if it fails:
```powershell
Stop-VM -Name "VM-Name" -Force
```

---

### Error: "No NVIDIA drivers found on host"

**Cause:** NVIDIA drivers not installed or not in expected location.

**Solution:**
1. Install latest NVIDIA drivers from nvidia.com/drivers
2. Restart host system
3. Verify with: `nvidia-smi`

---

### Error: "Method 'Clamp' not found"

**Cause:** Running on PowerShell 5.1 or older (Windows PowerShell).

**Solution:**
- Script is already updated to use compatible methods
- If you see this error, ensure you're using the latest version of the script
- Alternative: Use PowerShell 7+ from microsoft.com/powershell

---

### Error: GPU Not Detected in VM

**Cause:** Driver injection incomplete or GPU partition not configured.

**Solution:**
1. Check Device Manager in VM → Display Adapters
2. Should see "Microsoft Hyper-V GPU Partition Adapter"
3. If missing, re-run Option [3] (Inject GPU Drivers)
4. If "Generic Non-PnP Monitor", disable Hyper-V display adapter
5. Restart VM

---

### Performance: Low FPS or Stuttering

**Causes & Solutions:**

**1. Insufficient GPU Allocation**
- Increase GPU percentage (Option [2])
- Recommended: 50% for single VM, 40% each for two VMs

**2. Dynamic Memory Enabled** (shouldn't happen with this tool)
- Verify: `Get-VMMemory -VMName "VM-Name" | Select DynamicMemoryEnabled`
- Should be: `False`

**3. Driver Mismatch**
- Update host drivers first
- Then update VM drivers (Option [5])
- Host and VM should have identical driver versions

**4. Hyper-V Display Adapter Conflict**
- In VM Device Manager, disable "Microsoft Hyper-V Video"
- Only keep "Microsoft Hyper-V GPU Partition Adapter"

---

### Issue: Can't See GPU VRAM / Shows 4GB Limit

**Cause:** Using WMI instead of nvidia-smi (AdapterRAM is 32-bit).

**Solution:**
- Script automatically uses nvidia-smi for accurate readings
- If nvidia-smi not in PATH, add: `C:\Program Files\NVIDIA Corporation\NVSMI`
- Option [6] shows accurate VRAM via nvidia-smi

---

### Cleanup: Remove Failed VM

```powershell
# Remove VM
Remove-VM -Name "VM-Name" -Force

# Delete VHD
Remove-Item "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\VM-Name.vhdx" -Force
```

---

## 📊 Performance Expectations

### GPU Performance by Allocation

| Allocation | Use Case | Expected Performance |
|------------|----------|---------------------|
| **25%** | Light gaming, video playback | ~25% of host GPU |
| **50%** | Single VM gaming (recommended) | ~50% of host GPU |
| **75%** | Heavy workloads, ML training | ~75% of host GPU |
| **100%** | Single VM maximum performance | ~95% of host GPU |

### Real-World Examples

**RTX 4090 (50% allocation to VM):**
- Host: Can run desktop, browse, stream
- VM: 1440p gaming at 60-144 FPS (game dependent)
- Overhead: ~5-10% performance loss vs native

**RTX 3060 Ti (50% allocation):**
- VM: 1080p gaming at 60+ FPS (AAA titles)
- Host: Basic multitasking
- Overhead: ~10-15% performance loss

---

## 🔒 Limitations & Known Issues

### Graphics API Support
✅ **Supported:**
- DirectX 9, 10, 11, 12
- OpenGL (most versions)
- Compute workloads (CUDA, tensor)

❌ **Not Supported:**
- Vulkan API
- NVIDIA DLSS
- NVIDIA Reflex
- Ray tracing (limited or no support)
- Frame generation technologies

### VM Requirements
- **Generation 2 VMs only** (UEFI required)
- **NVIDIA GPUs only** (AMD not supported by this script)
- **Windows 10/11 guest OS** (Linux experimental, not documented here)
- **No nested virtualization** (VM can't run Hyper-V VMs)

### Driver Considerations
- **Same version required:** Host and VM drivers must match
- **Manual updates needed:** VM drivers don't auto-update
- **NVIDIA control panel:** Not available in VM (controlled via host)

---

## 🎯 Best Practices

### VM Configuration
✅ **DO:**
- Use static memory allocation (already done by script)
- Disable checkpoints for performance (already done)
- Allocate realistic GPU percentages (50% is sweet spot)
- Keep host drivers updated
- Sync VM drivers after host updates (Option [5])

❌ **DON'T:**
- Enable dynamic memory (causes instability)
- Use Hyper-V console for gaming (use VNC/RDP instead)
- Allocate >75% GPU to VM (leaves host unstable)
- Mix driver versions between host and VM

### Performance Optimization
1. **Use NVMe storage** for VM disks
2. **Allocate enough RAM** (16GB minimum for gaming VM)
3. **Use 1:1 CPU core ratio** (8 cores = 4 host, 4 VM)
4. **Install VB-Cable** for low-latency audio in VM
5. **Use Sunshine/Moonlight** for game streaming from VM

### Driver Management
```
Host Driver Update Workflow:
1. Update NVIDIA drivers on host
2. Restart host system
3. Power off ALL VMs completely
4. Run script → Option [5] for each VM
5. Start VMs and verify functionality
6. Check Device Manager in each VM
```

---

## 🚀 Advanced Usage

### Multiple VMs with GPU Access

**Scenario:** 2 VMs on RTX 4090

```powershell
# VM 1: Gaming-VM (40% GPU)
Select option: 2
VM Name: Gaming-VM
GPU Allocation: 40

# VM 2: Dev-VM (40% GPU)
Select option: 2
VM Name: Dev-VM
GPU Allocation: 40

# Remaining 20% for host
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

## 🔄 Maintenance Schedule

### Weekly
- Check for Windows updates in VMs
- Verify VM backups (if using backup solution)

### Monthly  
- Check for NVIDIA driver updates
- Update host drivers if available
- Sync VM drivers (Option [5])
- Check VM disk space usage

### Quarterly
- Review GPU allocation percentages
- Optimize VM configurations
- Clean up unused VMs
- Update this tool if new version available

---

## 📚 Additional Resources

### Documentation
- [Microsoft Hyper-V GPU-P Documentation](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/partition-assign-vm-gpu)
- [NVIDIA Driver Downloads](https://www.nvidia.com/Download/index.aspx)
- [PowerShell Hyper-V Module Reference](https://learn.microsoft.com/en-us/powershell/module/hyper-v/)

### Community
- r/VFIO - Subreddit for GPU passthrough discussions
- r/HyperV - Hyper-V specific community
- Discord servers for virtualization enthusiasts

### Tools Mentioned
- **VNC Server**: [RealVNC](https://www.realvnc.com/) or [TightVNC](https://www.tightvnc.com/)
- **VB-Cable**: [VB-Audio Virtual Cable](https://vb-audio.com/Cable/)
- **Sunshine/Moonlight**: [Sunshine](https://github.com/LizardByte/Sunshine) + [Moonlight](https://moonlight-stream.org/)

---

## 🐛 Reporting Issues

If you encounter bugs or have feature requests:

1. **Gather Information:**
   - PowerShell version: `$PSVersionTable.PSVersion`
   - Windows version: `winver`
   - GPU model: `nvidia-smi`
   - Error messages (full text)

2. **Check Existing Issues:**
   - Review troubleshooting section
   - Search closed issues on GitHub

3. **Create Detailed Report:**
   - Describe expected vs actual behavior
   - Include steps to reproduce
   - Attach relevant logs
   - Specify your system configuration

---

## 📝 Version History

### v3.0 (Current)
- ✨ Modern terminal UI with color-coded logging
- ✨ Quick preset configurations (Gaming/Dev/ML)
- ✨ Automated driver injection with smart detection
- ✨ Driver update/sync functionality
- ✨ Accurate VRAM detection via nvidia-smi
- ✨ Enhanced error handling with user-friendly messages
- ✨ Auto-elevation to Administrator
- ✨ Complete automation from creation to driver injection
- ✅ PowerShell 5.1 compatibility (Windows PowerShell)
- ✅ Secure Boot and TPM 2.0 configuration
- ✅ Smart partition detection and mounting
- ✅ Safe VHD mounting with random mount points
- ✅ Automatic cleanup on errors

### v2.0 (Previous)
- Basic VM creation
- Manual GPU partition configuration
- Basic driver injection
- Limited error handling

### v1.0 (Original)
- VM creation only
- No GPU features
- Manual configuration required

---

## 💡 Tips & Tricks

### Faster Windows Installation
Use Windows 11 with `autounattend.xml` to skip OOBE:
```xml
<!-- Place in ISO root for automated setup -->
```

### Reduce VM Boot Time
```powershell
# Disable unnecessary services in VM
Set-Service -Name "XboxGipSvc" -StartupType Disabled
Set-Service -Name "XboxNetApiSvc" -StartupType Disabled
```

### Optimal RAM Allocation
```
Gaming VM: 16GB (leaves 16GB for host with 32GB total)
Dev VM: 8-12GB (for development workloads)
ML VM: 24-32GB (for machine learning tasks)
```

### Check GPU Utilization
In VM, install GPU-Z or use Task Manager → Performance → GPU.

### Remote Desktop Performance
For best performance: Sunshine (VM) + Moonlight (client) > Parsec > RDP > VNC

---

## 🎮 Use Cases

### Gaming VM
- Play Windows-exclusive games on Linux host (via WSL2/Hyper-V)
- Isolate gaming environment from work environment
- Test games before installing on main system
- Stream games to other devices in home

### Development VM
- Test applications in isolated environment
- GPU-accelerated development (Unity, Unreal, Blender)
- CUDA/ML development without affecting host
- Multiple development environments on one machine

### Machine Learning
- Training models with GPU acceleration
- Isolated Python/CUDA environments
- Jupyter notebooks with GPU access
- TensorFlow/PyTorch development

### Content Creation
- Video editing with GPU acceleration (DaVinci Resolve)
- 3D rendering (Blender, Cinema 4D)
- Photo editing (Photoshop GPU features)
- Live streaming setup

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

## 🌟 Why Use This Tool?

### Before (Manual Process)
❌ 30-60 minutes per VM setup  
❌ Error-prone manual driver copying  
❌ Complex PowerShell commands to remember  
❌ Easy to misconfigure GPU partitions  
❌ No driver version tracking  

### After (Using This Tool)
✅ 5-10 minutes per VM setup  
✅ Automated driver detection and copying  
✅ Simple menu-driven interface  
✅ Optimized GPU partition calculations  
✅ Driver sync with one command  

---

## 🙏 Credits & Acknowledgments

Built upon the foundation of GPU-P (GPU Paravirtualization) technology developed by Microsoft for Windows Server and Hyper-V. This tool consolidates community knowledge and best practices into an accessible, automated solution.

**Special thanks to:**
- Microsoft Hyper-V team for GPU-P feature development
- NVIDIA for driver support
- r/VFIO and r/HyperV communities for shared knowledge
- Early testers and contributors

---

## 📜 License

This tool is provided as-is for educational and personal use. No warranty is provided. Use at your own risk.

**Disclaimer:** GPU virtualization requires compatible hardware and may not work with all GPU models or driver versions. Always backup important data before creating VMs.

---

**🎮 Happy Virtualizing! 🚀**

*Built for power users, streamlined for everyone.*

---

**Latest Version:** v3.0  
**Last Updated:** October 2025  
**Compatibility:** Windows 10/11 Pro, PowerShell 5.1+, NVIDIA GPUs

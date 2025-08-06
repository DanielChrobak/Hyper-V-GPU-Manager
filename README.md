# 🎮 Unified VM Manager - Complete VM Management Suite

A streamlined PowerShell tool for creating and managing Hyper-V virtual machines with integrated GPU partitioning and driver injection. This unified solution consolidates VM creation, GPU resource allocation, and NVIDIA driver management into a single, efficient terminal interface.

## ✨ Features

- **🚀 Automated VM Creation**: Complete VM setup with optimized configurations
- **🎯 GPU Partitioning**: Configurable GPU resource allocation (1-100% per VM)
- **💾 Driver Injection**: Direct NVIDIA driver installation into VM disk images
- **🔄 Driver Updates**: Keep VM and host GPU drivers synchronized 
- **🖥️ Simple Terminal UI**: Clean menu system with color-coded logging
- **⚙️ Complete VM Lifecycle**: Create, configure, and manage VMs from one tool
- **🔧 Flexible Configuration**: Test mode or custom settings for different needs
- **📊 Smart Partition Detection**: Automatic partition discovery and mounting

## 🔧 Prerequisites

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Windows 10 Pro | Windows 11 Pro |
| **RAM** | 8GB | 16GB+ |
| **CPU** | 4 cores | 6+ cores |
| **GPU** | NVIDIA GTX 1060+ | NVIDIA RTX series |
| **Storage** | 128GB free | 256GB+ SSD |
| **Virtualization** | Hyper-V enabled | Hyper-V + VT-d |

### Enable Hyper-V

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All
```

## 🚀 Quick Start

### 1. Download and Run

```powershell
# Run as Administrator (script will auto-elevate if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\Unified-VM-Manager.ps1
```

### 2. Menu Options Overview

The script presents 6 main options:

1. **Create New VM** - Basic VM creation without GPU features
2. **Create GPU Partition** - Add GPU partitioning to existing VM
3. **Add GPU Drivers to VM** - Inject NVIDIA drivers into VM disk
4. **Complete GPU Setup** - Full automated setup (VM + GPU + ready for drivers)
5. **Update GPU Drivers in VM** - Synchronize VM drivers with host (overwrite)
6. **Exit** - Close the application

## 📋 Detailed Workflow

### Option 1: Create New VM
- Choose between test values or custom configuration
- Configure RAM (minimum 2GB), CPU cores, and storage
- Automatic TPM setup for Windows 11 compatibility
- ISO attachment if provided
- Generation 2 VM with optimized settings

### Option 2: Create GPU Partition  
- Select existing VM from your system
- Choose GPU allocation percentage (1-100%)
- Automatic VM shutdown if running
- Advanced partition value calculations
- Memory mapping optimization (1GB low, 32GB high)

### Option 3: Add GPU Drivers to VM
- **Important**: Install Windows in VM first before using this option
- Mounts VM disk image safely
- Locates NVIDIA driver repository from host system
- Copies drivers and system files to VM
- Automatic cleanup and dismounting

### Option 4: Complete GPU Setup
- Combines Options 1 and 2 automatically
- Creates VM with immediate GPU partition setup
- **Note**: You must install the OS first, then use Option 3 for drivers

### Option 5: Update GPU Drivers in VM ⭐ NEW
- **Best Practice**: Keep VM drivers synchronized with host
- Overwrites existing VM drivers with current host versions
- Confirmation prompt before proceeding
- Same reliable process as initial driver injection
- Essential after host GPU driver updates

### Option 6: Exit
- Safely closes the application
- Returns to PowerShell prompt

## ⚙️ Configuration Details

### VM Settings (Automatic)
- **Generation**: 2 (UEFI support)
- **Memory**: Static allocation (no dynamic memory)
- **Checkpoints**: Disabled for better performance
- **Enhanced Session Mode**: Disabled
- **Guest Service Interface**: Disabled
- **TPM**: Enabled with local key protector

### GPU Partition Calculations
The script uses intelligent formulas for optimal performance:

```powershell
$maxValue = [int](($percentage / 100) * 1000000000)
$optValue = $maxValue - 1
$minValue = 1
```

Applied to:
- VRAM allocation
- Encode/Decode resources  
- Compute resources

### Test Mode Defaults
Quick testing configuration:
- **Name**: TestVM
- **RAM**: 8GB
- **CPU**: 4 cores
- **Storage**: 128GB
- **Path**: Default Hyper-V location

## 🔍 Logging System

The script provides detailed logging with timestamps and color coding:
- **INFO** (White): General information and progress
- **SUCCESS** (Green): Successful operations
- **WARN** (Yellow): Warnings and non-critical issues
- **ERROR** (Red): Errors requiring attention

Example log entries:
```
[2025-08-06 03:15:42][SUCCESS] VM 'TestVM' created successfully - RAM: 8GB, CPU: 4, TPM: True, ISO: True
[2025-08-06 03:20:15][WARN] This will overwrite existing GPU drivers with the latest version from the host
[2025-08-06 03:21:03][SUCCESS] GPU drivers updated successfully - VM drivers now match host version
```

## 🛠️ Post-Creation Setup

### After VM Creation:
1. **Start the VM** and install Windows using attached ISO
2. **Complete Windows setup** with internet connection
3. **Return to script** and use Option 3 to inject GPU drivers
4. **Install remote access solution** (VNC, RDP, etc.)
5. **Configure audio** (VB-Cable or similar)
6. **Setup display driver** for headless operation

### Driver Maintenance:
7. **Monitor host driver updates** - Check NVIDIA GeForce Experience or manual updates
8. **Update VM drivers** - Use Option 5 after any host GPU driver updates
9. **Verify compatibility** - Ensure both host and VM are running same driver version

### Important Notes:
- ⚠️ **Always install the OS before injecting drivers**
- ✅ **VM must be powered off for GPU partition and driver operations**
- 🔄 **Use remote desktop solutions instead of Hyper-V console for gaming**
- 🔄 **Keep drivers synchronized between host and VM for optimal performance**

## 🧪 Troubleshooting

### Common Issues:

**"VM already exists" Error:**
- Choose a different VM name or delete existing VM

**"No partitions found" Error:**
- Ensure Windows is fully installed in the VM
- VM must be completely powered off

**GPU Partition Fails:**
- Verify NVIDIA drivers are installed on host
- Ensure VM is Generation 2
- Check that VM is powered off

**Driver Injection/Update Fails:**
- Run PowerShell as Administrator
- Ensure VM hard disk is accessible
- Verify NVIDIA drivers exist in `C:\Windows\System32\DriverStore\FileRepository`
- Check that VM is completely powered off

**Performance Issues After Driver Update:**
- Restart both host and VM after driver updates
- Verify GPU partition allocation hasn't changed
- Check Windows Device Manager for driver conflicts

**Permission Issues:**
- Script auto-elevates, but manual elevation may be needed:
```powershell
Start-Process powershell.exe -Verb RunAs
```

## 🔧 Advanced Usage

### Driver Update Strategy
**Recommended Workflow:**
1. Update NVIDIA drivers on host system first
2. Test host system stability and performance
3. Power off gaming VMs completely
4. Run script and choose Option 5 for each VM
5. Start VMs and verify GPU functionality

### Custom VM Paths
The script prompts for VHD location with smart defaults:
- Default: `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`
- Custom paths supported for better storage management

### Manual GPU Percentage Tuning
- Start conservative (25-50%) for testing
- Increase gradually based on performance needs
- Monitor host system stability

### Driver Repository Location
The script automatically finds:
```
C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64*
```

## 🛡️ Security & Compatibility

- **Administrator Rights**: Required for Hyper-V operations
- **TPM 2.0**: Automatically configured for Windows 11
- **Secure Boot**: Enabled on Generation 2 VMs
- **UEFI**: Full support for modern operating systems
- **Legacy BIOS**: Not supported (Generation 2 only)
- **Driver Integrity**: Maintains driver signing and integrity during updates

## 📈 Performance Expectations

With proper configuration:
- **VM Performance**: ~85-95% of allocated resources
- **GPU Performance**: Scales with partition percentage
- **Gaming**: Suitable for most modern titles
- **Overhead**: Minimal with static memory allocation
- **Driver Sync**: Essential for maintaining optimal GPU performance

## 🔄 Workflow Summary

**Complete Setup Process:**
1. Run script as Administrator
2. Choose Option 4 (Complete GPU Setup)
3. Configure VM settings (or use test mode)
4. Wait for VM creation and GPU partition setup
5. Start VM and install Windows + drivers
6. Power off VM completely  
7. Run script again and choose Option 3
8. Install remote desktop solution in VM
9. Configure audio and display drivers
10. Ready for gaming!

**Driver Maintenance Process:**
1. Update host NVIDIA drivers
2. Power off all gaming VMs
3. Run script and choose Option 5 for each VM
4. Confirm driver update when prompted
5. Start VMs and verify functionality

## 🎯 Best Practices

- **Always backup** important VMs before making changes
- **Test with lower GPU percentages** first
- **Use static memory allocation** for gaming VMs  
- **Disable unnecessary integration services** for performance
- **Keep host NVIDIA drivers updated**
- **Synchronize VM drivers immediately after host updates**
- **Monitor system resources** during VM operation
- **Use confirmation prompts** - Don't skip the safety checks

## 🆕 Driver Update Features

The new driver update system provides:
- **Automatic Detection**: Finds latest NVIDIA drivers from host
- **Safe Overwriting**: Uses `-Force` parameter for reliable file replacement
- **User Confirmation**: Prevents accidental driver updates
- **Progress Logging**: Clear feedback during the update process
- **Error Handling**: Robust cleanup and error recovery
- **Version Synchronization**: Ensures host-VM driver compatibility

*Efficient VM Management with Synchronized Performance! 🎮*

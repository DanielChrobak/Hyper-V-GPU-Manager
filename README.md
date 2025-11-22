# Unified VM Manager
# Hyper-V GPU-PV Automation, Universal Driver Injection, and VM Provisioning

The **Unified VM Manager** is a fully automated PowerShell-based Hyper-V management framework that provisions virtual machines, configures GPU partitioning (GPU-PV), performs vendor-agnostic GPU driver detection, and injects full driver packages directly into Windows VM disks.

Unlike previous versions, this optimized edition is a **complete rewrite**, focused on:

• Accurate multi-vendor driver resolution (NVIDIA, AMD, Intel Arc/iGPU)  
• Correct DriverStore folder identification and copy behavior  
• Fully structured function architecture  
• Strong input validation and error recovery  
• Clean UI + detailed logging  
• Robust VHD/VHDX mounting and Windows-detection logic  
• Safer unmounting  
• Higher performance during file scanning  
• Consistent menu-driven workflow  
• Highly readable modular code design

The result is the most accurate, complete, and resilient GPU-PV management system available for Hyper-V.

====================================================================
# TABLE OF CONTENTS
====================================================================
1. Overview
2. System Requirements
3. Features
4. Installation
5. Running the Manager
6. Main Menu and Navigation
7. VM Creation System
8. GPU Partitioning System
9. Automatic GPU Driver Detection
10. INF Parsing & File Discovery Architecture
11. Driver Injection Workflow (Host → VM)
12. Virtual Disk Mounting & Windows Detection
13. Logging System
14. VM Application Deployment
15. List VMs & Host GPU Info
16. Supported & Unsupported GPU-PV Features
17. Troubleshooting
18. PowerShell API Usage (Programmatic Examples)
19. Advanced Configuration
20. License & Disclaimer

====================================================================
# 1. OVERVIEW
====================================================================

The Optimized Unified VM Manager automates the full lifecycle of GPU-accelerated Hyper-V virtual machines:

• Create new VMs with preset or custom templates  
• Partition GPUs using Microsoft GPU-PV  
• Auto-detect host GPU & locate correct driver INF  
• Parse INF to extract all required driver files  
• Locate each referenced file across System32, SysWOW64 & DriverStore  
• Copy both individual files and full DriverStore directories  
• Mount VM disk, inject files, unmount safely  
• Update drivers when the host GPU driver is updated  
• Display VM inventory and GPU partition details  
• Copy "VM Apps" installers into guest Windows profile  

The script works across:

• **NVIDIA (RTX, GTX, Quadro)**  
• **AMD Radeon / RDNA / RDNA2 / RDNA3**  
• **Intel Arc & Intel integrated graphics**  

All GPU types work using the same **registry → INF → file discovery → injection** pipeline.

====================================================================
# 2. SYSTEM REQUIREMENTS
====================================================================

Operating System:
• Windows 10 Pro/Enterprise 20H1+  
• Windows 11 Pro/Enterprise (recommended)  
• Server 2019/2022 (with Desktop Experience)

Hyper-V:
• Must be installed  
• Must support GPU-PV (modern Windows builds)

Hardware:
• CPU: 6-core minimum (8+ recommended)  
• RAM: 16 GB minimum (32 GB+ recommended)  
• GPU: Any modern GPU with WDDM 2.5+ driver  
• Disk: 128 GB SSD minimum (NVMe recommended)

Software:
• PowerShell 5.1+
• Administrator privileges
• GPU drivers installed on host

====================================================================
# 3. FEATURES
====================================================================

• Full VM creation wizard with presets  
• Complete GPU-PV partition management  
• Vendor-agnostic GPU detection  
• Full INF parsing and dependency extraction  
• Automatic driver file location system  
• Correct DriverStore folder assembly  
• Mount/unmount VHDX without letter conflicts  
• Detects Windows installations automatically  
• Driver injection with verification  
• VM Apps deployment to guest Downloads folder  
• Accurate GPU VRAM reporting (NVIDIA/AMD/Intel)  
• Menu system with arrow-key navigation  
• Colorized timestamped logging  
• Complete error recovery system  
• Multi-GPU support  

====================================================================
# 4. INSTALLATION
====================================================================

Enable Hyper-V:

    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All

Set execution policy:

    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

Place this file in any folder. Example:

    C:\VMTools\Optimized-Unified-VM-Manager.ps1

Optional folder structure if using app deployment:

    ScriptDirectory\
    ├── Optimized-Unified-VM-Manager.ps1
    └── VM Apps\
        ├── Sunshine.zip
        ├── VB-Cable.zip
        └── VirtualAudio.zip

====================================================================
# 5. RUNNING THE MANAGER
====================================================================

    PS> .\Optimized-Unified-VM-Manager.ps1

The script will auto-elevate if required.

====================================================================
# 6. MAIN MENU AND NAVIGATION
====================================================================

Navigation uses arrow keys:

• UP/DOWN = move selection  
• ENTER   = confirm  
• ESC     = go back (in submenus)

Main Menu Options:

1. Create New VM  
2. Configure GPU Partition  
3. Inject GPU Drivers (Auto-Detect)  
4. Complete Setup (VM + GPU + Drivers)  
5. Update VM Drivers (Auto-Detect)  
6. List VMs & GPU Info  
7. Copy VM Apps to Downloads  
8. Exit  

====================================================================
# 7. VM CREATION SYSTEM
====================================================================

Preset types:

• Gaming: 16GB RAM, 8 CPU, 256GB disk  
• Development: 8GB RAM, 4 CPU, 128GB disk  
• ML Training: 32GB RAM, 12 CPU, 512GB disk  
• Custom configuration (full manual control)

VM Characteristics:

• Generation 2  
• UEFI firmware  
• Secure Boot + TPM 2.0  
• Static memory  
• Checkpoints disabled  
• DVD boot priority  
• Automatic VHDX creation  

Every setting is validated, and error handling prevents partial VM creation.

====================================================================
# 8. GPU PARTITIONING SYSTEM
====================================================================

GPU-PV allows allocating percentages of a physical GPU to a VM.

The script configures:

• VRAM  
• ENCODE  
• DECODE  
• COMPUTE  

All values are mapped from 1–100% → 1–1,000,000,000 (GPU-PV internal scale).

Example 50% allocation:

    MaxPartitionVRAM = 500000000
    MaxPartitionEncode = 500000000
    ...

The VM must be powered off before applying changes.

====================================================================
# 9. AUTOMATIC GPU DRIVER DETECTION
====================================================================

The optimized script uses a multi-stage detection system:

1. Enumerate all display-class devices via Win32_PnPSignedDriver  
2. Filter out Microsoft Basic Display Adapter  
3. Read full driver metadata (version, provider, date, INF path)  
4. Resolve the real INF file from registry Class GUID:
   HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}

5. Confirm INF exists in C:\Windows\INF  
6. Pass INF to file extraction engine  

Works on systems with multiple GPUs.

====================================================================
# 10. INF PARSING & FILE DISCOVERY ARCHITECTURE
====================================================================

The INF parsing engine extracts:

• .sys  
• .dll  
• .exe  
• .cat  
• .inf  
• .bin  
• .cpa  
• .vp  

All referenced filenames are collected uniquely.

Driver discovery checks:

1. DriverStore\FileRepository (full folder copy)  
2. System32  
3. SysWOW64  

DriverStore folders are copied **intact** to preserve full package structure.

This version improves:

• Regex accuracy  
• Duplicate elimination  
• Handling of vendor-specific subfolders  
• Case-insensitive matching  
• Multi-match grouping  

====================================================================
# 11. DRIVER INJECTION WORKFLOW (HOST → VM)
====================================================================

Steps:

1. Select VM  
2. Detect GPU  
3. Extract driver metadata  
4. Parse INF  
5. Build file list  
6. Mount VM VHDX  
7. Detect Windows directory  
8. Create HostDriverStore inside VM  
9. Copy all DriverStore folders  
10. Copy all individual files to System32/SysWOW64  
11. Verify copy success  
12. Unmount VHDX cleanly  

Drivers install automatically on next VM boot.

====================================================================
# 12. VIRTUAL DISK MOUNTING & WINDOWS DETECTION
====================================================================

• Mount-VHD -NoDriveLetter  
• Refresh disk info (Update-Disk)  
• Find Windows partition (>10 GB)  
• Create temp mount folder  
• Add-PartitionAccessPath  
• Confirm Windows\System32 exists  

Unmounting:

• Remove access path  
• Dismount-VHD  
• Delete mount folder  

The optimized script also:

• Handles locked disks  
• Handles missing partitions  
• Detects non-Windows volumes  
• Recovers from partially mounted states  

====================================================================
# 13. LOGGING SYSTEM
====================================================================

Each log entry:

[HH:MM:SS] SYMBOL message

Symbols:

> INFO (cyan)  
+ SUCCESS (green)  
! WARNING (yellow)  
X ERROR (red)  
~ HEADER (magenta)  

Logging is used everywhere, including system operations, file copy progress, and error reporting.

====================================================================
# 14. VM APPLICATION DEPLOYMENT
====================================================================

If "VM Apps" folder exists, the script can copy .zip utilities directly into the Windows user's Downloads folder inside the VM.

Process:

1. Choose VM  
2. Script detects installed OS  
3. Script finds primary user profile  
4. Script copies all zip files to:
   C:\Users\<User>\Downloads\VM Apps\

====================================================================
# 15. LIST VMs & HOST GPU INFO
====================================================================

VM list includes:

• Name  
• State  
• RAM  
• CPU  
• Storage size  
• GPU allocation %  

Host GPU list includes:

• Name  
• Driver version  
• Driver date  
• Accurate VRAM:
  - NVIDIA: nvidia-smi
  - AMD: rocm-smi
  - Intel: registry HardwareInformation.qxvram  

Fallback: WMI AdapterRAM (less accurate)

====================================================================
# 16. SUPPORTED & UNSUPPORTED GPU-PV FEATURES
====================================================================

Supported:

• DirectX 9–12  
• Hardware decoding/encoding  
• Most games  
• ML frameworks (with separate CUDA install)  
• Stable VRAM partitioning  

Not Supported (GPU-PV limitations):

• Vulkan  
• DLSS / Frame Generation  
• CUDA runtime libs (install inside VM)  
• OpenGL extensions (emulated via DX12 → slower)  

====================================================================
# 17. TROUBLESHOOTING
====================================================================

== GPU missing in VM ==
Cause: no partition / no drivers  
Fix: partition GPU → inject drivers → reboot

== "Windows not detected" during injection ==
Cause: VM OS not installed  
Fix: install Windows, shut down VM, retry

== Wrong GPU selected ==
Fix: reinstall GPU drivers on host → reboot

== Driver injection fails: not enough space ==
Fix: expand virtual disk via Resize-VHD

====================================================================
# 18. POWERSHELL PROGRAMMATIC EXAMPLES
====================================================================

Examples include:

• VM creation via Initialize-VM  
• Querying GPU allocation  
• Listing host GPUs with VRAM  
• Changing partition percentage  
• Setting custom storage locations  

====================================================================
# 19. ADVANCED CONFIGURATION
====================================================================

Options include:

• Custom VM path  
• Custom disk sizes  
• Changing GPU allocation post-creation  
• Manual driver injection  
• Using multiple GPUs for separate VMs  

====================================================================
# 20. LICENSE & DISCLAIMER
====================================================================

Provided AS-IS with no warranty.  
GPU-PV support depends on hardware, OS version, and driver versions.

Use at your own risk and always back up important data before performing VM operations.

====================================================================

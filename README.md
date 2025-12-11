# GPU Virtualization Manager

A comprehensive PowerShell tool for GPU partitioning (GPU-PV) in Hyper-V virtual machines. Simplifies the process of sharing your GPU with VMs for gaming, development, machine learning, and other GPU-accelerated workloads.

## Features

- **Automated VM Creation** with presets for common use cases
- **GPU Partitioning** - Allocate GPU resources (1-100%) to VMs
- **Driver Injection** - Automatically inject host GPU drivers into VM disks
- **Automated Windows Installation** - Create unattended installation ISOs
- **VM Management** - View, configure, and delete VMs with GPU assignments
- **Error Handling** - Comprehensive error messages with pauses for readability
- **PowerShell 5.1 Compatible** - Works on Windows 10/11 without PowerShell 7

---

## Requirements

### System Requirements
- **Windows 10/11 Pro, Enterprise, or Education**
- **Hyper-V** enabled (will not work on Home editions)
- **Administrator privileges** (script auto-elevates)
- **Partitionable GPU** with drivers installed on host
  - Most modern NVIDIA, AMD, and Intel GPUs support GPU-PV
  - Check GPU compatibility with Menu Option 6: "GPU Info"

### Optional Requirements
- **Windows ADK** (Assessment and Deployment Kit) for automated installation ISO creation
  - Download: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
  - Only required if you want to use the automated installation feature
  - If not installed, autounattend.xml will be saved to Desktop for manual use

---

## Installation

1. Download `GPU-PV-Manager.ps1`
2. Right-click → **Run with PowerShell**
3. Script will auto-elevate to Administrator if needed

**Alternative:** Run from PowerShell:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "GPU-PV-Manager.ps1"
```

---

## Navigation

- **UP/DOWN arrows** - Navigate menu items
- **ENTER** - Select option
- **ESC** - Cancel/Go back
- **Press Enter prompts** - Continue after operations complete

---

## Menu Options

### 1. Create VM
Creates Generation 2 VMs optimized for GPU partitioning.

**VM Presets:**
| Preset | CPU Cores | RAM | Storage | Use Case |
|--------|-----------|-----|---------|----------|
| Gaming | 8 | 16GB | 256GB | Gaming, high-performance apps |
| Development | 4 | 8GB | 128GB | Development, testing |
| ML Training | 12 | 32GB | 512GB | Machine learning, AI workloads |
| Custom | User-defined | User-defined | User-defined | Fully customizable |

**VM Configuration:**
- Generation 2 (UEFI-based)
- Secure Boot enabled (On by default)
- TPM 2.0 enabled with local key protector
- Static memory allocation (no dynamic memory)
- Checkpoints disabled for performance
- Custom automatic start/stop actions configured
- Boot order: DVD → Hard Disk (for installation)

**Automated Installation (Optional):**
When providing an ISO path, you can enable automated Windows installation:
- **Creates modified ISO** with `autounattend.xml` injected
- **Automatic disk partitioning** - Creates UEFI partitions (WINRE, EFI, MSR, Windows)
- **Skips setup screens** - Bypasses EULA, keyboard selection, privacy settings
- **User interaction required:**
  - Windows edition selection during installation
  - User account creation after first boot
- **Requires Windows ADK** for ISO creation (oscdimg.exe)
- **Fallback:** If ADK not installed, autounattend.xml saved to Desktop

**File Locations:**
- VHDs: `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`
- Auto-install ISOs: `C:\ProgramData\HyperV-ISOs\`

---

### 2. GPU Partition
Allocates GPU resources to a virtual machine.

**Process:**
1. Select target VM from list (shows current state and specs)
2. Choose partitionable GPU from host
3. Specify GPU allocation percentage (1-100%)
4. VM automatically stops if running (graceful shutdown with 60s timeout)
5. Configures GPU partition adapter with resource limits:
   - **VRAM** (Video RAM)
   - **Encode** (Video encoding)
   - **Decode** (Video decoding)
   - **Compute** (GPU compute/CUDA/OpenCL)
6. Sets memory-mapped I/O:
   - **Low MMIO:** 1GB
   - **High MMIO:** 32GB
7. Enables guest-controlled cache types

**Requirements:**
- VM must be stopped (script handles this automatically)
- GPU must support partitioning (check with GPU Info menu)

**Notes:**
- Allocation percentage applies to all resource types equally
- Removing GPU partition also cleans up MMIO settings
- Can reallocate different percentage by running again

---

### 3. Unassign GPU
Removes GPU partition and cleans all driver files from VM disk.

**Process:**
1. Confirms GPU partition exists on selected VM
2. Prompts for confirmation
3. Stops VM if running (graceful shutdown)
4. Removes GPU partition adapter
5. Resets memory-mapped I/O settings:
   - Low MMIO: 0
   - High MMIO: 0
   - Guest-controlled cache: Disabled
6. Mounts VM disk to `C:\ProgramData\HyperV-Mounts\VMMount_<random>`
7. **Cleans driver files:**
   - Deletes entire `Windows\System32\HostDriverStore` directory
   - Removes individual driver files from System32 and SysWow64
   - Reports files/folders removed
8. Unmounts disk and cleans up mount point

**Error Handling:**
- **VM without Windows installed:** Gracefully handles mount failures
  - GPU adapter and MMIO settings still removed
  - Displays "GPU REMOVAL PARTIAL" message
  - Informs user driver cleanup was skipped
- **All errors pause** for user to read before returning to menu

---

### 4. Install Drivers
Injects host GPU drivers into VM disk automatically.

**Requirements:**
- **GPU partition must be assigned first** (enforced by script)
- **Windows must be installed** in the VM
- **VM must have VHDX attached**
- **VM will be stopped** automatically if running

**Detection Process:**
1. Identifies GPU from partition adapter (matches VEN/DEV IDs)
2. Queries WMI for GPU info (Win32_VideoController)
3. Searches registry: `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968...}`
4. Locates GPU's INF file in `C:\Windows\INF\`
5. Parses INF for driver file references:
   - `.sys`, `.dll`, `.exe`, `.cat`, `.inf`, `.bin`, `.vp`, `.cpa`
6. Searches for files in:
   - `C:\Windows\System32\DriverStore\FileRepository` (recursive)
   - `C:\Windows\System32` (non-recursive)
   - `C:\Windows\SysWow64` (non-recursive)

**Copy Process:**
1. Mounts VM disk to `C:\ProgramData\HyperV-Mounts\VMMount_<random>`
2. Creates `Windows\System32\HostDriverStore\FileRepository` in VM
3. **Copies driver folders** with all contents (preserves structure)
4. **Copies system files** to matching paths (System32/SysWow64)
5. Reports total files and folders injected
6. Unmounts disk and cleans up

**Error Messages:**
- **No GPU partition assigned:** Directs user to assign GPU first
- **GPU driver not found on host:** Ensure GPU drivers installed on host
- **No VHD found:** VM may not have disk attached
- **Windows not installed:** Clear error with pause before returning to menu

**Success Output:**
```
DRIVER INJECTION COMPLETE
Injected 156 files + 3 folders
```

---

### 5. List VMs
Displays comprehensive overview of all Hyper-V VMs.

**Information Shown:**

| Column | Description | Example |
|--------|-------------|---------|
| Icon | State indicator | `[*]` Running, `[ ]` Off, `[~]` Other |
| VM Name | Virtual machine name | Dev-VM, Gaming-VM |
| State | Current state | Running, Off, Saved, Paused |
| CPU | Processor count | 4, 8, 12 |
| RAM(GB) | Memory allocation | 8, 16, 32 |
| Storage | VHDX size in GB | 128, 256, 512 |
| GPU | GPU model and allocation | RTX 4090 (50%), None |

**Color Coding:**
- **Green:** Running VMs
- **Gray:** Stopped VMs
- **Yellow:** Other states (Saved, Paused, etc.)

**GPU Detection:**
- Shows friendly GPU name (e.g., "NVIDIA GeForce RTX 4090")
- Displays allocation percentage
- Shows "None" if no GPU assigned

**Example Output:**
```
+----------------------------------------------------------------------------------------+
| | VM Name            | State   | CPU | RAM(GB) | Storage | GPU                      |
+----------------------------------------------------------------------------------------+
| [*] Gaming-VM        | Running | 8   | 16      | 256     | RTX 4090 (75%)           |
| [ ] Dev-VM           | Off     | 4   | 8       | 128     | RTX 4090 (25%)           |
| [ ] Test-VM          | Off     | 4   | 8       | 64      | None                     |
+----------------------------------------------------------------------------------------+
```

---

### 6. GPU Info
Displays all physical GPUs with detailed information and partitioning capability.

**Information Shown:**

| Column | Description |
|--------|-------------|
| # | GPU index number |
| Status | `[OK]` Working, `[X]` Error/Issue |
| GPU Name | Full device name (e.g., "NVIDIA GeForce RTX 4090") |
| Driver Version | Current driver version |
| Provider | Driver provider (NVIDIA, AMD, Intel) |
| Partitionable | `Yes` (Cyan) or `No` (Gray) |

**Detection:**
- Queries WMI `Win32_VideoController`
- Excludes Microsoft/Remote Display adapters
- Matches VEN/DEV IDs against `Get-VMHostPartitionableGpu` output
- Correctly identifies NVIDIA, AMD, and Intel GPUs

**Partitionability Check:**
- Compares GPU hardware IDs with Hyper-V partitionable GPU list
- Only GPUs marked "Yes" can be used for GPU partitioning

**Example Output:**
```
+-------------------------------------------------------------------------------------------+
| # | Status | GPU Name                      | Driver Version | Provider | Partitionable |
+-------------------------------------------------------------------------------------------+
| 1 | [OK]   | NVIDIA GeForce RTX 4090       | 31.0.15.5123   | NVIDIA   | Yes           |
| 2 | [OK]   | Intel UHD Graphics 770        | 31.0.101.4146  | Intel    | No            |
+-------------------------------------------------------------------------------------------+
```

---

### 7. Delete VM
Completely removes a virtual machine with optional file cleanup.

**Process:**
1. Select VM to delete
2. Displays VM information:
   - VM name and current state
   - VHD path (if exists)
   - Auto-install ISO path (if from this script)
   - External ISO path (if manually attached, will not be deleted)
3. Confirms deletion with user
4. Asks whether to delete associated files (VHD and auto-install ISO)
5. Stops VM if running (graceful shutdown)
6. Removes GPU partition if exists
7. Deletes VM from Hyper-V
8. Optionally deletes files:
   - **VHDX file** (if user confirmed)
   - **Auto-install ISO** (only if created by this script)
   - **External ISOs** are never deleted (preserved)

**File Handling:**
- **VHD always shown** if attached to VM
- **Auto-install ISOs** (in `C:\ProgramData\HyperV-ISOs\`) offered for deletion
- **External ISOs** logged but never deleted
- User chooses whether to delete files or preserve them

**Success Output:**
```
VM DELETED SUCCESSFULLY
VM 'Dev-VM' has been removed
Associated files deleted
```

**Or if files preserved:**
```
VM DELETED SUCCESSFULLY
VM 'Dev-VM' has been removed
VHD preserved: C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\Dev-VM.vhdx
ISO preserved: C:\ProgramData\HyperV-ISOs\Dev-VM-AutoInstall.iso
```

---

## Complete Workflow Examples

### New Gaming VM from Scratch
```
1. Menu → Create VM
   - Select "Gaming" preset
   - Enter VM name (or press Enter for default "Gaming-VM")
   - Enter Windows ISO path: C:\ISOs\Win11.iso
   - Choose "Y" for automated installation

2. Wait for ISO creation (automated installation ISO)
   - Script creates modified ISO with autounattend.xml
   - VM created and ISO attached

3. Start VM in Hyper-V Manager
   - Windows installation proceeds automatically
   - Select Windows edition when prompted
   - Create user account after first boot

4. After Windows installation completes, shut down VM

5. Menu → GPU Partition
   - Select your VM
   - Choose GPU (e.g., RTX 4090)
   - Allocate 50% (or desired percentage)

6. Menu → Install Drivers
   - Select your VM
   - Script injects GPU drivers automatically

7. Start VM
   - GPU appears in Device Manager
   - Ready for gaming/GPU workloads!
```

### Update GPU Drivers After Host Update
```
1. Update GPU drivers on host system (download from manufacturer)

2. Run GPU-PV-Manager.ps1

3. Menu → Install Drivers
   - Select first VM
   - Wait for injection to complete
   - Press Enter

4. Repeat for each VM with GPU partition

5. Restart all VMs to load new drivers
```

### Reassign GPU Between VMs
```
1. Menu → Unassign GPU
   - Select VM currently using GPU
   - Confirm removal
   - Driver files cleaned automatically

2. Menu → GPU Partition
   - Select different VM
   - Choose same GPU
   - Allocate desired percentage

3. Menu → Install Drivers
   - Select the new VM
   - Drivers injected

4. Start new VM - GPU now available
```

### Share GPU Between Multiple VMs
```
1. Menu → GPU Partition
   - Select first VM
   - Choose GPU
   - Allocate 50%

2. Menu → Install Drivers
   - Select first VM

3. Menu → GPU Partition
   - Select second VM
   - Choose same GPU
   - Allocate 50% (total 100% allocated)

4. Menu → Install Drivers
   - Select second VM

5. Both VMs can now use the GPU (not simultaneously if total > 100%)

Note: Total allocation can exceed 100%, but only one VM can use GPU at a time
```

---

## Technical Details

### File Paths
- **VHD Storage:** `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`
- **ISO Storage:** `C:\ProgramData\HyperV-ISOs\` (automated installation ISOs)
- **Temporary Mounts:** `C:\ProgramData\HyperV-Mounts\VMMount_<random>`
- **GPU Registry:** `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`

### Automated Installation
The script creates a modified Windows installation ISO with `autounattend.xml` that:
- **Partitioning:** Creates UEFI GPT layout (WINRE, EFI, MSR, Windows partitions)
- **Automation:** Accepts EULA, skips keyboard/locale screens, disables privacy prompts
- **Locale:** en-US (configurable by editing XML)
- **User Interaction:** Edition selection and account creation still required
- **Boot Prompt:** Uses `efisys_noprompt.bin` if available to skip boot menu

**Requirements:**
- Windows ADK installed (specifically oscdimg.exe)
- Source ISO must be Windows 10/11 installation media

**Fallback:**
- If ADK not found, autounattend.xml is copied to Desktop
- User can manually copy it to installation media root

### VM Configuration Details
All created VMs are configured with:
- **Generation:** 2 (UEFI-based, required for GPU-PV)
- **Firmware:**
  - Secure Boot: On (SecureBootTemplate: "MicrosoftUEFICertificateAuthority")
  - TPM: Enabled with new local key protector
- **Memory:**
  - Static allocation (DynamicMemoryEnabled: $false)
  - Startup memory set to specified GB
- **Processor:**
  - Count set to specified cores
- **Storage:**
  - VHDX format (dynamic expansion)
  - SCSI controller
- **Checkpoints:**
  - Type: Disabled
  - Automatic checkpoints: Disabled
- **Automatic Actions:**
  - Start: Nothing (manual start)
  - Stop: ShutDown (graceful)

### VM Selection Interface
When selecting VMs, the interface displays:
- **State Icons:**
  - `[*]` Running VM (green)
  - `[ ]` Stopped VM (gray)
  - `[~]` VM in other state (yellow) - Saved, Paused, etc.
- **VM Details:**
  - Name (padded to 20 characters)
  - State with brackets
  - CPU core count
  - RAM in GB
  - GPU allocation percentage or "None"

### Error Handling & User Experience
- **All errors pause** before returning to menu (user must press Enter)
- **Descriptive error messages** with suggested actions
- **Graceful handling** of missing Windows installations
- **Partial success reporting** when some operations succeed
- **Timeout handling** for VM shutdown (60 seconds)
- **Forced shutdown fallback** if graceful shutdown times out

### Security Features
- **Administrator elevation:** Auto-prompts if not running as admin
- **Secure mount points:** ACL protection (SYSTEM and Administrators only)
- **TPM & Secure Boot:** Enabled on all created VMs
- **Execution policy bypass:** Only for script execution, doesn't change system policy

### GPU Driver Detection
The script uses multiple methods to identify GPU drivers:
1. **Registry analysis:** Searches GPU class registry for matching device IDs
2. **INF parsing:** Extracts file references from driver INF files
3. **File location:** Searches multiple paths (DriverStore, System32, SysWow64)
4. **VEN/DEV matching:** Matches partition adapter to host GPU by hardware IDs

### Memory-Mapped I/O (MMIO)
GPU partitioning requires MMIO space for GPU communication:
- **Low MMIO:** 1GB (below 4GB address space)
- **High MMIO:** 32GB (above 4GB address space)
- **Guest Cache Control:** Enabled (allows VM to manage GPU cache)

These settings are:
- **Applied** when assigning GPU partition
- **Reset to 0** when removing GPU partition
- **Required** for proper GPU function in VM

---

## Compatibility

### Tested Configurations
- **Windows 10 Pro** (21H2 and later)
- **Windows 11 Pro/Enterprise** (all versions)
- **PowerShell 5.1** (default on Windows 10/11)
- **NVIDIA GPUs:** GeForce RTX 20/30/40 series, RTX A-series
- **AMD GPUs:** RX 6000/7000 series (driver dependent)
- **Intel GPUs:** Arc A-series, some integrated GPUs

### Known Limitations
- **Windows Home editions:** Hyper-V not available
- **Older GPUs:** May not support GPU-PV (check with GPU Info menu)
- **Multiple VMs using GPU:** Cannot run simultaneously if total allocation > 100%
- **Driver updates:** VMs need driver re-injection after host driver updates
- **Live migration:** Not supported with GPU partition

---

## Troubleshooting

### GPU Not Detected in VM
1. **Check GPU partition assignment:**
   - Menu → List VMs
   - Verify GPU column shows allocation

2. **Verify drivers installed:**
   - Menu → Install Drivers
   - Select VM and run driver injection

3. **Check Device Manager in VM:**
   - Should see GPU with warning (before drivers)
   - Should work properly after drivers installed

4. **Restart VM after driver installation**

### "No Partitionable GPUs Found"
1. **Check GPU support:**
   - Menu → GPU Info
   - Look for "Yes" in Partitionable column

2. **Update GPU drivers on host**

3. **Enable GPU partitioning in Hyper-V:**
   ```powershell
   Set-VMHost -EnableGpuPartitioning $true
   ```

4. **Check BIOS settings:**
   - VT-d/IOMMU must be enabled
   - Virtualization support enabled

### "Windows Not Installed" Error
This error appears when trying to inject drivers into a VM without Windows:

1. **Install Windows first:**
   - Start VM from ISO
   - Complete Windows installation
   - Shut down VM

2. **Then run driver injection:**
   - Menu → Install Drivers
   - Select VM

### Automated Installation Not Working
1. **Check if ADK installed:**
   - Look for: `C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\`

2. **Install Windows ADK:**
   - Download from Microsoft
   - Only need "Deployment Tools" component

3. **Fallback option:**
   - autounattend.xml saved to Desktop
   - Copy to USB/ISO manually
   - Place in root of installation media

### VM Won't Start After GPU Assignment
1. **Check MMIO settings:**
   ```powershell
   Get-VM "VM-Name" | Select-Object LowMemoryMappedIoSpace, HighMemoryMappedIoSpace
   ```
   Should show: 1GB and 32GB

2. **Verify Secure Boot:**
   ```powershell
   Get-VMFirmware "VM-Name"
   ```
   Secure Boot should be On

3. **Check event logs:**
   - Windows Event Viewer → Hyper-V-Worker logs

### Script Errors After Updates
If you encounter syntax errors:

1. **Check PowerShell version:**
   ```powershell
   $PSVersionTable.PSVersion
   ```
   Should be 5.1 or higher

2. **Re-download script** (may have been updated)

3. **Run as Administrator** (script auto-elevates but can be manually run)

---

## Advanced Usage

### Customizing VM Presets
Edit lines 767-770 in the script to add/modify presets:
```powershell
$script:VMPresets = @(
    @{Label="Your Custom | 16CPU, 64GB, 1TB"; Name="Custom-VM"; CPU=16; RAM=64; Storage=1024},
    # ... existing presets
)
```

### Custom Automated Installation XML
Modify the `New-AutoUnattendXML` function (lines 28-125) to customize:
- Language/locale settings
- Time zone
- Product key
- Computer name
- Partition layout

### Scripted VM Creation
Call functions directly from PowerShell:
```powershell
# Source the script
. .\GPU-PV-Manager.ps1

# Create VM
$config = @{
    Name = "My-VM"
    CPU = 8
    RAM = 16
    Storage = 256
    Path = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
    ISO = "C:\ISOs\Win11.iso"
}
New-GpuVM -Config $config

# Assign GPU (50% allocation)
Set-GPUPartition -VMName "My-VM" -Pct 50 -GPUPath "<GPU-Instance-Path>" -GPUName "RTX 4090"

# Install drivers
Install-GPUDrivers -VMName "My-VM"
```

### Batch Operations
Process multiple VMs:
```powershell
# Update drivers on all VMs with GPU partitions
Get-VM | Where-Object { Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue } | ForEach-Object {
    Write-Host "Updating drivers for $($_.Name)"
    Install-GPUDrivers -VMName $_.Name
}
```

---

## Credits & License

**GPU-PV-Manager** is provided as-is under the MIT License.

### MIT License
```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Free for personal, educational, and commercial use. No warranty provided.**

---

## Support

For issues, questions, or contributions:
- Check the Troubleshooting section above
- Review the FAQ
- Ensure you're using the latest version of the script

**Note:** This is a community tool. Support is best-effort and not guaranteed.

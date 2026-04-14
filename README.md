# Hyper-V GPU Paravirtualization Manager

A comprehensive PowerShell tool for GPU partitioning (GPU-PV) in Hyper-V virtual machines. Simplifies the process of sharing partitionable host devices (display GPUs and other accelerators) with VMs for gaming, development, machine learning, and related workloads.

## Features

- **Automated VM Creation** with presets for common use cases
- **GPU Partitioning** - Allocate resources (1-100%) per partition adapter, including multiple partitionable devices on the same VM
- **Driver Injection** - Automatically inject host partition-device drivers into VM disks using package-aware discovery with INF fallback
- **Unattended Install Media** - Create setup media with injected `autounattend.xml`
- **Non-Interactive CLI Commands** - Run repeatable operations in scripts and pipelines (`-Command create-vm`, `set-gpu`, etc.)
- **VM Profile Templates** - Save reusable VM presets (VM name, CPU/RAM/storage, ISO, unattended defaults) and pick them from Create VM
- **Reusable API Layer** - Automation and future GUI clients call a stable API surface instead of menu-only flows
- **VM Management** - View, configure, and delete VMs with GPU assignments
- **Error Handling** - Clear blocking errors with pauses, plus non-blocking warnings for partial driver resolution/copy scenarios
- **PowerShell 5.1 Compatible** - Works on Windows 10/11 without PowerShell 7

---

## Requirements

### System Requirements
- **Windows 10/11 Pro, Enterprise, or Education**
- **Hyper-V** enabled (will not work on Home editions)
- **Administrator privileges** (script auto-elevates)
- **Partitionable host device** with drivers installed on host
   - Commonly includes modern NVIDIA/AMD/Intel display GPUs
   - Can also include non-display accelerators that Hyper-V reports as partitionable (for example NPU/ComputeAccelerator)
   - Check display-adapter compatibility with Menu Option 7: "GPU Info"

### Optional Requirements
- **Windows ADK** (Assessment and Deployment Kit) for unattended installation ISO creation
  - Download: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
   - Only required if you want to build unattended install ISO media from the script
  - If not installed, autounattend.xml will be saved to Desktop for manual use

---

## Installation

1. Download or clone this repository (keep the `src` folder intact)
2. Run `Run-HyperV-GPU-Virtualization-Manager.cmd`
3. Script will auto-elevate to Administrator if needed

**Alternative:** Run from PowerShell:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command help
```

### Project Layout

- `Run-HyperV-GPU-Virtualization-Manager.cmd` - Recommended launcher (handles ExecutionPolicy bypass)
- `HyperV-GPU-Virtualization-Manager.ps1` - Main bootstrap entry script (interactive + non-interactive command mode)
- `src\Core\` - Domain and platform modules used by all hosts
- `src\Core\Gpu\Gpu.Helpers.ps1` - GPU discovery and driver lookup helpers
- `src\Core\Main.Actions.ps1` - Core VM/GPU action implementations (supports interactive and non-interactive execution)
- `src\Api\Manager.Api.ps1` - API surface returning structured result objects
- `src\Cli\Interactive.Menu.ps1` - Menu-driven UI host
- `src\Cli\Command.Dispatcher.ps1` - Command-based CLI host
- `src\*.ps1` - Compatibility shims that dot-source the new Core module paths

### Non-Interactive CLI Mode

The script now supports command-based execution for automation.

```powershell
# List available commands
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command help

# Create a VM from preset defaults
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command create-vm -Preset gaming -VMName Gaming-VM -IsoPath C:\ISOs\Win11.iso -OverwriteVhd

# Assign 50% of a specific partitionable GPU to a VM
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command set-gpu -VMName Gaming-VM -GpuPath "PCIROOT(...)" -GpuPercent 50

# Inject drivers for all assigned GPU partitions on a VM
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command install-drivers -VMName Gaming-VM -All -SkipExisting

# Output machine-readable JSON
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command list-vms -Json
```

Available command values:
- `interactive`
- `preflight`
- `create-vm`
- `set-gpu`
- `remove-gpu`
- `install-drivers`
- `delete-vm`
- `list-vms`
- `list-gpus`
- `help`

### VM Profile Templates

VM profile templates are managed from the interactive menu (`VM Profiles`) and appear as selectable entries in `Create VM`.

- **Profile store:** `<project root>\.hyperv-gpu-manager.vm-profiles.json`
- **Create VM order:** built-in presets first, then saved VM profile templates

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

**Unattended Installation Media (Optional):**
When providing an ISO path, you can build unattended Windows setup media:
- **Creates modified ISO** with `autounattend.xml` injected
- **Automatic disk partitioning** - Creates UEFI partitions (WINRE, EFI, MSR, Windows)
- **Skips setup screens** - Bypasses EULA, privacy settings, etc
- **Optional edition auto-selection** - During VM creation, you can pick a listed install image index (or press Enter to keep manual edition selection during setup)
- **Still requires user interaction:**
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
2. Choose partitionable device from host
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
- Selected device must support partitioning

**Notes:**
- Allocation percentage applies to all resource types equally
- Some hosts report Encode capacity as `UInt64::MaxValue` (`18446744073709551615`). The script ignores that sentinel value and percentage-scales Encode using the fallback baseline (`1000000000`) for consistent behavior.
- Removing GPU partition also cleans up MMIO settings
- Running GPU Partition again for the same GPU updates that adapter's percentage
- Running GPU Partition for a different GPU adds another adapter with its own percentage (when `-InstancePath` is supported on the host)
- Non-display partitionable devices are shown with a class tag in the selection menu (for example `[COMPUTEACCELERATOR]`)

---

### 3. Unassign GPU
Removes selected GPU partition(s) from a VM, with optional driver file cleanup.

**Process:**
1. Confirms GPU partition(s) exist on selected VM
2. Lets you choose one GPU partition, all GPU partitions, or cancel
3. Prompts to confirm partition removal
4. Asks whether to also remove matching injected driver files from the VM disk
5. Stops VM if running (graceful shutdown)
6. Removes selected GPU partition adapter(s)
7. Resets memory-mapped I/O settings only when no GPU partitions remain:
   - Low MMIO: 0
   - High MMIO: 0
   - Guest-controlled cache: Disabled
8. If cleanup is chosen, mounts VM disk to `C:\ProgramData\HyperV-Mounts\VMMount_<guid>` and removes matching driver files/folders for the selected GPU partition(s)
   - Cleanup prefers manifest-based removal (exact tracked paths) and falls back to resolver-based matching when no manifest exists
9. Unmounts disk and cleans up mount point

**Error Handling:**
- **VM without Windows installed:** Gracefully handles mount failures
  - GPU adapter and MMIO settings still removed
  - Displays "GPU REMOVAL PARTIAL" message
  - Informs user driver cleanup was skipped
- **Blocking errors pause** for user to read before returning to menu

---

### 4. Install Drivers
Injects host GPU drivers into VM disk automatically.

**Requirements:**
- **GPU partition must be assigned first** (enforced by script)
- **Windows must be installed** in the VM
- **VM must have VHDX attached**
- **VM will be stopped** automatically if running

**Selection Flow:**
- If multiple GPU partitions are assigned to the VM, you can choose:
   - A specific assigned GPU partition
   - **All assigned GPU partitions**
   - **Cancel**
- You can choose whether to skip unchanged files already present in the VM disk (uses SHA256 hash comparison)
- For non-display devices, success depends on whether the host has an installed vendor package with resolvable signed-driver associations/INF references

**Detection Process:**
1. Resolves selected partition device metadata from adapter instance path (class + VEN/DEV IDs)
2. Finds host signed driver with class-aware preference (preferred class -> Display -> first matching VEN/DEV driver)
3. Resolves package files using WMI association class `Win32_PnPSignedDriverCIMDataFile`
4. Includes driver service binary path via `Win32_SystemDriver` when available
5. Resolves and analyzes INF as fallback/enrichment (`C:\Windows\INF\<oem#.inf>`)
6. Classifies files into:
   - DriverStore folders (`C:\Windows\System32\DriverStore\FileRepository\...`)
   - Direct system file destinations (`System32`, `SysWow64`, `INF`, etc.)
7. Reports unresolved INF references as warnings and tracks resolver strategy (`WmiAssociation`, `InfFallback`, or `WmiAssociation+InfFallback`)

**Copy Process:**
1. Mounts VM disk to `C:\ProgramData\HyperV-Mounts\VMMount_<guid>`
2. Creates `Windows\System32\HostDriverStore\FileRepository` in VM
3. **Copies driver folders** for selected GPU(s)
4. **Copies system files** to matching paths (System32/SysWow64/INF/etc.)
   - Any DriverStore-style destination is remapped to `HostDriverStore\FileRepository` for safe offline injection
5. If skip-existing is enabled, only hash-identical files are skipped; changed files are updated
6. Reports copied/skipped counts
7. Writes a driver manifest in the VM (`Windows\System32\HostDriverStore\gpu-driver-manifest.json`) for safer targeted cleanup
8. Unmounts disk and cleans up

**Driver Manifest Content:**
- One entry per selected partition device/driver package, including VM name, captured UTC timestamp, resolver strategy, device ID/name, INF path, unresolved references, and tracked destination folders/files
- Used by **Unassign GPU** cleanup as first choice (exact tracked paths), with resolver fallback when no manifest entry is available

**Error Messages:**
- **No GPU partition assigned:** Directs user to assign GPU first
- **No matching device driver(s):** Ensure the selected partition device has an installed host driver package
- **No VHD found:** VM may not have disk attached
- **Windows not installed:** Clear error with pause before returning to menu

**Troubleshooting Non-Display Partition Devices:**
- If selection succeeds but no files are resolved, verify the host has a complete vendor driver package installed for that device class
- Re-run driver injection and review warnings for package association and unresolved INF references
- Confirm the selected adapter's device class/IDs match an installed signed driver package on the host

**Success Output:**
```
DRIVER INJECTION COMPLETE
Copied 156 file(s) across 3 folder copy operation(s)
Skipped 420 existing file(s)
```

---

### 5. Delete VM
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

### 6. List VMs
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

### 7. GPU Info
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
- Matches VEN/DEV IDs against Hyper-V partitionable device output (`Get-VMHostPartitionableGpu` on newer builds, `Get-VMPartitionableGpu` on older builds)
- Correctly identifies NVIDIA, AMD, and Intel GPUs

**Partitionability Check:**
- Compares GPU hardware IDs with Hyper-V partitionable GPU list
- GPUs marked "Yes" can be targeted through display-adapter workflows
- Non-display partitionable devices (for example NPU/ComputeAccelerator) may not appear in this screen because it is based on `Win32_VideoController`

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

## Complete Workflow Examples

### New Gaming VM from Scratch
```
1. Menu → Create VM
   - Select "Gaming" preset
   - Enter VM name (or press Enter for default "Gaming-VM")
   - Enter Windows ISO path: C:\ISOs\Win11.iso
   - Choose "Y" to build unattended install media

2. Wait for ISO creation (unattended installation ISO)
   - Script creates modified ISO with autounattend.xml
   - VM created and ISO attached

3. Start VM in Hyper-V Manager
   - Windows setup runs mostly unattended
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

2. Run HyperV-GPU-Virtualization-Manager.ps1

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

5. Both VMs can now use the GPU

```

---

## Technical Details

### File Paths
- **VHD Storage:** `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`
- **ISO Storage:** `C:\ProgramData\HyperV-ISOs\` (unattended installation ISOs)
- **Temporary Mounts:** `C:\ProgramData\HyperV-Mounts\VMMount_<guid>` (`<guid>` is a 32-character GUID string without hyphens)
- **VM Profile Store:** `<project root>\.hyperv-gpu-manager.vm-profiles.json`
- **Host Driver Store (inside mounted guest):** `Windows\System32\HostDriverStore\FileRepository\`
- **Driver Manifest (inside mounted guest):** `Windows\System32\HostDriverStore\gpu-driver-manifest.json`
- **GPU Registry:** `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`

### Driver Store Isolation
To improve offline driver injection reliability, any destination path that targets guest DriverStore (`\Windows\System32\DriverStore\FileRepository\...`) is remapped to guest HostDriverStore (`\Windows\System32\HostDriverStore\FileRepository\...`) before copy.

This keeps injected host package content isolated from guest-managed DriverStore operations while preserving predictable cleanup via manifest and resolver fallback logic.

### Unattended Installation Media
The script creates a modified Windows installation ISO with `autounattend.xml` that:
- **Partitioning:** Creates UEFI GPT layout (WINRE, EFI, MSR, Windows partitions)
- **Automation:** Accepts EULA, disables privacy prompts, etc
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
- **Blocking errors pause** before returning to menu (user must press Enter)
- **Non-blocking warnings continue** when partial driver discovery/copy results are acceptable
- **Descriptive error messages** with suggested actions
- **Graceful handling** of missing Windows installations
- **Partial success reporting** when some operations succeed
- **Timeout handling** for VM shutdown (graceful attempt, then forced power-off fallback)

### Security Features
- **Administrator elevation:** Auto-prompts if not running as admin
- **Secure mount points:** ACL protection (SYSTEM and Administrators only)
- **TPM & Secure Boot:** Enabled on all created VMs
- **Execution policy bypass:** Only for script execution, doesn't change system policy

### GPU Driver Detection
The script uses a multi-tier strategy to identify driver content:
1. **Partition device correlation:** Uses partition adapter instance path and VEN/DEV IDs to identify candidate signed drivers
2. **Class-aware lookup:** Prefers signed drivers matching the selected device class, then falls back to Display, then first matching candidate
3. **WMI package association (primary):** Enumerates package files using `Win32_PnPSignedDriverCIMDataFile`
4. **Service binary inclusion:** Includes driver service binary path from `Win32_SystemDriver` when available
5. **INF enrichment/fallback:** Resolves INF path and extracts referenced files (`.sys`, `.dll`, `.exe`, `.cat`, etc.)
6. **Path classification:** Splits results into DriverStore folders and direct system destinations
7. **Strategy tracking:** Records resolver mode (`WmiAssociation`, `InfFallback`, `WmiAssociation+InfFallback`) and unresolved INF references in manifest/logs

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

## Advanced Usage

### Customizing VM Presets
Use the interactive `VM Profiles` menu to create/edit VM template entries.

```powershell
# Open interactive menu and manage VM templates
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command interactive
```

To add/modify entries directly, edit the VM profile JSON and keep this shape per profile:

```json
{
   "Name": "workstation",
   "VmName": "Workstation-VM",
   "Cpu": 12,
   "RamGB": 48,
   "StorageGB": 1024,
   "VhdPath": "C:\\ProgramData\\Microsoft\\Windows\\Virtual Hard Disks\\",
   "IsoPath": "C:\\ISOs\\Win11.iso",
   "EnableAutoInstall": true,
   "InstallImageIndex": 0,
   "UnattendUsername": "User",
   "UnattendPassword": "",
   "OverwriteVhd": false
}
```

### Custom Unattended Installation XML
Modify `$script:AutoXMLTemplate` in `src\Core\AutoInstallIso.ps1` to customize:
- Language/locale settings
- Time zone
- Product key
- Computer name
- Partition layout

### API-First Scripting
Call the API layer directly from PowerShell:
```powershell
# Load modules without starting the interactive menu
$root = "C:\Path\To\Hyper-V-GPU-Manager-main"
. "$root\src\Core\Config.Helpers.ps1"
. "$root\src\Core\Gpu\Gpu.Helpers.ps1"
. "$root\src\Core\Vhd.Operations.ps1"
. "$root\src\Core\Vm.Helpers.ps1"
. "$root\src\Core\AutoInstallIso.ps1"
. "$root\src\Core\Main.Actions.ps1"
. "$root\src\Api\Manager.Api.ps1"

# Create VM via API
$create = Invoke-HyperVGpuApiCreateVm -Name "My-VM" -Cpu 8 -RamGB 16 -StorageGB 256 -VhdPath "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\" -IsoPath "C:\ISOs\Win11.iso" -OverwriteVhd

# Assign GPU partition via API
$gpu = Invoke-HyperVGpuApiSetGpu -VmName "My-VM" -Percent 50 -GpuPath "PCIROOT(...)"

# Inject drivers for all assigned partitions
$drivers = Invoke-HyperVGpuApiInstallDrivers -VmName "My-VM" -All -SkipExisting
```

### Batch Operations
Process multiple VMs:
```powershell
# Update drivers on all VMs with GPU partitions
Get-VM | Where-Object { Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue } | ForEach-Object {
    Write-Host "Updating drivers for $($_.Name)"
   InstallDrivers -VMName $_.Name
}
```

---

## Credits & License

**Hyper-V GPU Paravirtualization Manager** is provided as-is under the MIT License.

**Free for personal, educational, and commercial use. No warranty provided.**

---

**Note:** This is a community tool. Support is best-effort and not guaranteed.

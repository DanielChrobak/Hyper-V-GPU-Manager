# Hyper-V GPU Paravirtualization Manager

A comprehensive, robust PowerShell tool for GPU partitioning (GPU-PV) in Hyper-V virtual machines. 

Automatically handles VM creation, resource allocation, and complex offline driver injection so you can easily share host GPUs (and other compute accelerators) with your VMs for gaming, machine learning, and hardware-accelerated workloads.

## Key Features

- **Global OS Compatibility** - Built using language-agnostic Security Identifiers (SIDs) and locale-independent ACLs to ensure folder isolation and disk mounting work out-of-the-box perfectly on non-English Windows environments.
- **Multi-Disk VM Support** - Fully supports VMs with multiple attached drives. Intelligently sums total storage sizes for list views, natively deep-cleans all attached drives upon deletion, and provides an interactive "System Disk" selector to mount the correct drive for driver injection and driver cleanup.
- **Automated Windows Setup** - Read Windows ISOs to interactively extract and choose Windows Install Images (e.g., Windows 11 Enterprise vs Pro). Create modified unattended ISOs that entirely bypass setup screens, with optional persistent local account credentials injected directly via `autounattend.xml`.
- **Reusable VM Profiles** - Save your preferred VM setup (including names, specs, target ISO, unattended credentials, and auto-install settings) as a profile to launch highly customized VMs in a single click from the main menu.
- **GPU Partitioning** - Allocate VRAM and Compute resources (1-100%) per adapter. Easily bind multiple partitionable devices to a single VM.
- **Smart Driver Injection & Cleanup** - Interrogates host packages and INFs to cleanly inject display and compute drivers strictly offline into the VM. Safely isolates injected drivers to prevent Windows Update conflicts and writes a detailed JSON manifest inside the VM for pixel-perfect cleanup operations later.
- **Non-Interactive CLI Layer** - Power users and deployment pipelines can run all operations via headless command triggers (`-Command create-vm`, `set-gpu`, `install-drivers`, etc.).
- **Reusable API Layer** - Modern scripts and UIs can seamlessly invoke the Core APIs internally to retrieve full JSON objects instead of strings.

---

## Requirements

### System Requirements
- **Windows 10/11 Pro, Enterprise, Education, or Server**
- **Hyper-V** enabled (will not work on Home editions)
- **Administrator privileges** (script auto-elevates)
- **Partitionable host device** with drivers installed on host
   - Commonly includes modern NVIDIA/AMD/Intel display GPUs
   - Also fully supports non-display accelerators that Hyper-V reports as partitionable (e.g., NPU/ComputeAccelerator)

### Optional Requirements
- **Windows ADK** for automated ISO creation:
  - Download: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
  - *Only required if you specify an ISO and choose Unattended Install.* If ADK is absent, an `autounattend.xml` setup script will just be saved to your Desktop for physical fallback use.

---

## Installation

1. Download or clone this repository (keep the `src` folder intact).
2. Double-click `Run-HyperV-GPU-Virtualization-Manager.cmd`
3. The script will safely auto-elevate to Administrator and load the interactive menu.

**Alternative:** Run directly from PowerShell:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1"
```

---

## The Interactive Menu Workflow

The script features a fully interactive UI. Navigate using **Up/Down Arrows** and **Enter**.

### 1. Create VM
Creates Generation 2 VMs optimized for GPU partitioning (Secure Boot, TPM 2.0, static memory, Checkpoints disabled).
- **Pick Presets or Profiles**: Choose built-in presets (Gaming, Development, Machine Learning), map it out entirely 'Custom', or load one of your saved custom **VM Profiles**.
- **Automated Windows Setup**: When an ISO is provided, the script analyzes it. You can explicitly choose an Install Index (like Windows 11 Enterprise), and provide an offline admin Username/Password. The script creates a silent, zero-touch bootable ISO.

### 2. GPU Partition
Allocates GPU resources to a virtual machine.
- Select target VM (VM automatically executes a graceful stop if running).
- Choose any partitionable device from your host (includes displays and NPUs).
- Specify allocation percentage (1-100%). Modifies VRAM, Encode, Decode, Compute appropriately.
- Instantiates underlying Memory-Mapped I/O safely (1GB Low / 32GB High MMIO boundaries).

### 3. Unassign GPU
Removes selected GPU partition(s) from a VM, with optional deep driver cleanup.
- Pick specific GPU partitions to yank, or remove all partitions.
- Automatically asks to trigger an internal offline mount of the VM's disk(s). Uses an interactive System Disk selector if multiple virtual drives are attached.
- Utilizes the `gpu-driver-manifest.json` tracker inside the guest disk to safely purge the exact driver paths it injected, falling back to heuristic scanning when manifest entries are absent.

### 4. Install Drivers
Injects host GPU drivers into VM disks automatically. **(Run this while the VM is offline, AFTER allocating a GPU)**
- Select a VM and which assigned GPU partition you want to fulfill drivers for.
- Support for **Multi-Drive Setup Check**: Uses `Select-VMSystemDisk` to ensure drivers aren't accidentally written to secondary storage attachpoints.
- **Deep Target Injection** mapping isolates your Host-backed driver files in the guest offline `HostDriverStore` to cleanly bypass OS validation blocks.
- Smart checking dynamically skips injecting unchanged files (`-SkipExisting` hash checks).

### 5. VM Profiles
Manage templates for repeat virtualization without answering prompts.
- Review existing, Default, or Delete profiles. Profiles natively store CPU/RAM/VHD targets, automated credentials, and install image logic.

### 6. Delete VM
A complete destructive cleanup wizard.
- Inspects the Hyper-V layout and discovers **ALL** VHDs attached to it.
- Detaches GPUs, destroys the VM node, safely iterates through destroying all respective multi-drive `.vhdx` components, and purges the script-generated Auto-Install ISO without touching your external vanilla ISOs.

### 7. List VMs & 8. GPU Info
Comprehensive readout interfaces for analyzing running topologies, multi-disk total capacities, execution states, and raw hardware Partition Registry compatibility (including ID tracking for discrete devices).

---

## Headless CLI Engine (Non-Interactive Mode)

Perfect for Intune, Terraform, Ansible, or custom deployment scripting.

```powershell
# List available commands
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command help

# Create a VM from preset defaults mapping an Unattended ISO
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command create-vm -Preset gaming -VMName Gaming-VM -IsoPath C:\ISOs\Win11.iso -OverwriteVhd

# Assign 50% of a specific partitionable GPU to a VM
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command set-gpu -VMName Gaming-VM -GpuPath "PCIROOT(...)" -GpuPercent 50

# Interrogate and deeply offline-install drivers for all assigned partitions while skipping existing files
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command install-drivers -VMName Gaming-VM -All -SkipExisting

# Remove all GPU components cleanly with automated disk file cleanup
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command remove-gpu -VMName Gaming-VM -All -CleanDrivers

# Output machine-readable JSON for GUI integration
powershell.exe -ExecutionPolicy Bypass -File "HyperV-GPU-Virtualization-Manager.ps1" -Command list-vms -Json
```

---

## Technical Details & Core Architecture

### Project Layout
- `Run-HyperV-GPU-Virtualization-Manager.cmd` - Recommended launcher (handles automatic ExecutionPolicy bypass).
- `HyperV-GPU-Virtualization-Manager.ps1` - Main bootstrap script serving Interactive Menu and Command mode routers.
- `src\Api\Manager.Api.ps1` - Clean API surface returning structured PowerShell models and dynamic JSON capability handling multiple disks logic internally.
- `src\Core\Main.Actions.ps1` - Foundational implementations backing all operations.
- `.hyperv-gpu-manager.vm-profiles.json` - Persistent cache for VM Profiles.

### Path Conventions & Driver Isolation
- **VHD Storage:** `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`
- **Temporary Mount Processing:** `C:\ProgramData\HyperV-Mounts\VMMount_<guid>\` (Secured against language locale differences employing `S-1-5-18`/`S-1-5-32-544` System/Admin ACL SIDs).
- **Guest Driver Store Check:** Offline injections that target `\Windows\System32\DriverStore\FileRepository\...` are dynamically reassigned to `\Windows\System32\HostDriverStore\FileRepository\...` to permanently isolate the process from Guest Windows Driver restrictions.
- **Manifestation:** Injected drivers log their footprint into `Windows\System32\HostDriverStore\gpu-driver-manifest.json` ensuring exact precision when calling **Unassign GPU**.
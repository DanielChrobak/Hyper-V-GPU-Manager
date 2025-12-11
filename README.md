# GPU Virtualization Manager

A streamlined PowerShell tool for sharing your GPU with Hyper-V virtual machines. Ideal for gaming, development, or ML workloads needing GPU acceleration.

## What Does This Do?

This tool simplifies GPU partitioning for Hyper-V:

1. **Creates Gen2 VMs** with Secure Boot and TPM enabled
2. **Partitions GPU resources** by percentage to VMs
3. **Injects GPU drivers** directly into VM disks

## Requirements

- Windows 10/11 Pro/Enterprise (Hyper-V required)
- Administrator privileges (auto-elevates)
- Partitionable GPU with drivers installed on host
- Sufficient host resources for your VM configurations

## Quick Start

1. Save as `GPU-PV-Manager.ps1`
2. Right-click → Run with PowerShell (auto-elevates to Administrator)
3. Navigate with UP/DOWN arrows, ENTER to select, ESC to cancel

---

## Menu Options

### 1. Create VM
Creates Generation 2 VMs with presets or custom specifications.

**Presets:**
- **Gaming:** 8 CPU cores, 16GB RAM, 256GB storage
- **Development:** 4 CPU cores, 8GB RAM, 128GB storage
- **ML Training:** 12 CPU cores, 32GB RAM, 512GB storage

**VM Configuration:**
- Generation 2 (UEFI)
- Secure Boot enabled
- TPM 2.0 enabled (key protector configured)
- Static memory (dynamic memory disabled)
- Checkpoints disabled
- Automatic start/stop actions configured
- Optional ISO attachment for OS installation
- VHDXs stored in: `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`

**Note:** VM name can be customized when selecting a preset.

### 2. GPU Partition
Allocates GPU resources (1-100%) to a virtual machine.

**Process:**
1. Select target VM (automatically stops if running)
2. Choose partitionable GPU from host
3. Specify GPU allocation percentage (1-100%)
4. Script configures partition adapter with resource limits:
   - VRAM (Video RAM)
   - Encode (video encoding)
   - Decode (video decoding)
   - Compute (GPU compute)
5. Sets memory-mapped I/O spaces:
   - Low MMIO: 1GB
   - High MMIO: 32GB
6. Enables guest-controlled cache types

**Note:** VM must be stopped. Script will attempt graceful shutdown if running.

### 3. Unassign GPU
Removes GPU partition and cleans driver files from VM.

**Process:**
1. Confirms GPU partition exists on selected VM
2. Prompts for confirmation
3. Stops VM if running
4. Removes GPU partition adapter
5. Resets MMIO settings (Low/High to 0, guest cache control disabled)
6. Mounts VM disk to `C:\ProgramData\HyperV-Mounts\VMMount_<random>`
7. Deletes `Windows\System32\HostDriverStore` contents
8. Reports files/folders removed
9. Unmounts disk and cleans up mount point

**Error Handling:**
- Gracefully handles VMs without Windows installed
- Reports partial success if disk mounting fails
- GPU adapter and MMIO settings still removed even if driver cleanup fails

### 4. Install Drivers
Injects host GPU drivers into VM disk.

**Detection Process:**
1. Queries GPU via WMI (Win32_VideoController)
2. Searches registry: `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968...}`
3. Locates GPU's INF file in `C:\Windows\INF\`
4. Parses INF for driver file references (.sys, .dll, .exe, .cat, .bin, .vp, .cpa)
5. Searches for files in:
   - `C:\Windows\System32\DriverStore\FileRepository` (recursive)
   - `C:\Windows\System32` (non-recursive)
   - `C:\Windows\SysWow64` (non-recursive)

**Copy Process:**
1. Stops VM if running
2. Mounts VM disk to `C:\ProgramData\HyperV-Mounts\VMMount_<random>`
3. Creates `Windows\System32\HostDriverStore\FileRepository` in VM
4. Copies DriverStore folders (with all contents)
5. Copies System32/SysWow64 files to matching VM paths
6. Reports total files and folders injected
7. Unmounts disk

**Requirements:**
- Windows must be installed in VM
- VM must have VHDX attached
- VM will be stopped automatically

### 5. List VMs
Displays comprehensive table of all Hyper-V VMs.

**Columns:**
- **State Icon:** `[*]` Running, `[ ]` Off, `[~]` Other states
- **VM Name:** Truncated to 24 chars if needed
- **State:** Running, Off, Saved, etc.
- **CPU:** Processor count
- **RAM(GB):** Memory in GB (assigned or startup)
- **Storage:** VHDX size in GB
- **GPU:** Model name and allocation % (e.g., "RTX 4090 (50%)") or "None"

**Color Coding:**
- Green: Running VMs
- Gray: Stopped VMs
- Yellow: Other states

### 6. GPU Info
Displays all physical GPUs with partitioning capability status.

**Information Shown:**
- **GPU Name:** Full device name (e.g., "NVIDIA GeForce RTX 4090")
- **Status Icon:** `[OK]` for working GPUs, `[X]` for issues
- **Driver Version:** Current driver version
- **Provider:** Driver provider name (e.g., "NVIDIA")
- **Device Status:** OK or error state
- **Partitionability:** `[Partitionable]` (Cyan) or `[Not Partitionable]` (Gray)

**Detection:**
- Queries WMI Win32_VideoController
- Excludes Microsoft/Remote Display adapters
- Matches VEN/DEV IDs against `Get-VMHostPartitionableGpu` output
- Properly detects NVIDIA, AMD, and Intel GPUs

---

## Workflows

### New Gaming VM from Scratch
1. **Create VM** → Select Gaming preset → Enter VM name → Provide Windows ISO path
2. Start VM in Hyper-V Manager and install Windows
3. Shut down VM after Windows installation completes
4. **GPU Partition** → Select VM → Choose GPU → Allocate percentage (e.g., 50%)
5. **Install Drivers** → Select VM → Choose same GPU
6. Start VM - GPU should now be detected in Device Manager

### Update GPU Drivers
1. Update GPU drivers on host system
2. Run script → **Install Drivers** → Select each VM
3. Restart VMs to load new drivers

### Remove GPU from VM
1. **Unassign GPU** → Select VM → Confirm removal
2. (Optional) **GPU Partition** to reassign to different VM

### Delete VM Completely
1. **Unassign GPU** (if GPU assigned)
2. Close script and open Hyper-V Manager
3. Delete VM and virtual hard disk

---

## Technical Details

### File Paths
- **VHD Storage:** `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\`
- **Temporary Mounts:** `C:\ProgramData\HyperV-Mounts\VMMount_<random>`
- **GPU Registry:** `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`

### VM Selection Interface
When selecting VMs, the script displays:
- `[*]` Running VM
- `[ ]` Stopped VM
- `[~]` VM in other state (Saved, Paused, etc.)
- CPU count, RAM, and current GPU allocation

### Error Handling
- Gracefully handles VMs without Windows installed
- Automatically stops running VMs when needed (with timeout)
- Provides detailed logging with timestamps
- Safe mounting with ACL protection for mount points

### Security
- Requires Administrator elevation (auto-prompts)
- Secure mount points with restricted ACLs (SYSTEM and Administrators only)
- TPM and Secure Boot enabled on created VMs
- Execution policy bypass for script execution

---

## License

MIT License - Free for personal and educational use. No warranty provided.

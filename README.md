# GPU Virtualization Manager

A streamlined PowerShell tool for sharing your GPU with Hyper-V virtual machines. Ideal for gaming, development, or ML workloads needing GPU acceleration.

## What Does This Do?

This tool simplifies GPU partitioning for Hyper-V:

1. **Creates VMs** optimized for GPU passthrough
2. **Partitions GPU resources** by percentage to VMs
3. **Injects GPU drivers** directly into VM disks

## Requirements

- Windows 10/11 Pro (Hyper-V required)
- Administrator privileges (auto-elevates)
- Partitionable GPU with drivers installed
- 6+ CPU cores, 16GB+ RAM recommended

## Quick Start

1. Save as `GPU-PV-Manager.ps1`
2. Right-click → Run with PowerShell
3. Navigate with arrows, Enter to select, ESC to cancel

---

## Menu Options

### 1. Create VM
Generates Gen2 VMs with presets or custom specs.

**Presets:**
- Gaming: 8CPU, 16GB RAM, 256GB storage
- Development: 4CPU, 8GB RAM, 128GB storage
- ML Training: 12CPU, 32GB RAM, 512GB storage

**Features:**
- Secure Boot + TPM enabled
- Optional ISO attachment
- Conflicts disabled (checkpoints, etc.)

### 2. GPU Partition
Allocates GPU slice (1-100%) to a VM.

**Process:**
- Select stopped VM
- Choose partitionable GPU
- Set VRAM/Encode/Decode/Compute limits
- Configures MMIO spaces

**Note:** VM must be off.

### 3. Unassign GPU
Removes GPU access and cleans VM drivers.

**Actions:**
- Detaches partition adapter
- Resets MMIO settings
- Mounts VHDX, wipes HostDriverStore
- Handles non-Windows disks gracefully

### 4. Install Drivers
Copies host GPU drivers into VM.

**Detection:**
- Parses INF for required files
- Searches DriverStore/System32/SysWow64
- Copies folders/files to VM's HostDriverStore

**Requirements:** Windows installed, VM off.

### 5. List VMs
Table view of all VMs.

**Columns:**
- Name, State, CPU, RAM(GB), Storage(GB)
- GPU model, Allocation %

### 6. GPU Info
Lists detected GPUs with driver/status info.

---

## Workflows

### New Gaming VM
1. Create VM → Gaming preset → 50% GPU
2. Install Windows via Hyper-V Manager
3. Install Drivers → Select GPU
4. Boot VM

### Driver Update
1. Update host GPU drivers
2. Install Drivers on target VM(s)
3. Restart VMs

### Cleanup Old VM
1. Unassign GPU
2. Delete VM in Hyper-V Manager

## License

MIT: Free for personal/educational use. No warranty.

# GPU Virtualization Manager

A simple PowerShell tool that lets you share your computer's GPU with virtual machines running in Hyper-V. Perfect for gaming VMs, development environments, or any VM that needs graphics acceleration.

## What Does This Do?

This tool automates three things that are normally complicated:

1. **Creates virtual machines** with proper settings for GPU sharing
2. **Assigns a percentage of your GPU** to each VM (you choose how much)
3. **Installs GPU drivers** automatically inside the VM

## Requirements

- **Windows 10/11 Pro** (Home edition doesn't have Hyper-V)
- **Hyper-V enabled** (the tool will tell you if it's not)
- **Administrator rights** (script will auto-elevate)
- **A GPU with drivers installed** on your main computer
- **At least 16GB RAM** and **6+ CPU cores** recommended

## Quick Start

1. **Download** `GPU-PV-Manager.ps1`
2. **Right-click** the script and select "Run with PowerShell"
3. The script automatically requests admin rights if needed
4. Use **arrow keys** to navigate menus, **Enter** to select, **ESC** to cancel

That's it! The menu will guide you through everything.

---

## Complete Setup Guide

### First Time Setup (New VM)

**Step 1: Run "Complete Setup"**
- Select **"Complete Setup"** from main menu
- Choose a preset (Gaming, Development, or ML Training) or make a custom configuration
- Pick your GPU and how much to allocate (50% is a good starting point)
- Optionally provide a Windows ISO path

**Step 2: Install Windows**
- Open **Hyper-V Manager** (search in Start menu)
- Start your new VM
- Go through Windows installation like normal
- **Shut down the VM** when done

**Step 3: Install Drivers (if not done automatically)**
- Run the script again
- Select **"Install Drivers"**
- Choose your VM and GPU
- The script copies all necessary driver files

**Step 4: Start Your VM**
- Start the VM from Hyper-V Manager
- The GPU will be visible in Device Manager
- Install your games/apps and enjoy!

---

## Menu Options Explained

### 1. Create VM
Creates a new virtual machine with your chosen specifications.

**What you choose:**
- Name for your VM
- RAM (how much memory)
- CPU cores
- Storage size
- Optional: Windows ISO for installation

**What it does:**
- Creates a Generation 2 VM (modern UEFI)
- Disables features that conflict with GPU sharing
- Configures security (Secure Boot, TPM)
- Attaches your ISO so you can install Windows

**When to use:** Creating a brand new VM from scratch

---

### 2. GPU Partition
Assigns a percentage of your GPU to an existing VM.

**What you choose:**
- Which VM to configure
- Which GPU (if you have multiple)
- Percentage to allocate (1-100%)

**What it does:**
- Configures Hyper-V to share your GPU with the VM
- Sets up memory mappings for GPU access
- Reserves GPU resources for that VM

**When to use:** 
- After creating a new VM
- Changing how much GPU a VM gets
- Switching which GPU a VM uses

**Note:** VM must be powered off

---

### 3. Unassign GPU
Removes GPU access from a VM and cleans up driver files.

**What you choose:**
- Which VM to remove GPU from

**What it does:**
- Removes the GPU partition
- Cleans up driver files from VM disk
- Resets GPU-related settings

**When to use:**
- You don't need GPU in that VM anymore
- Starting fresh with different GPU
- Troubleshooting GPU issues

**Note:** VM must be powered off, Windows must be installed

---

### 4. Install Drivers
Automatically detects and installs GPU drivers inside a VM.

**What you choose:**
- Which VM to install drivers in
- Which GPU's drivers to copy

**What it does:**
- Scans your computer for GPU drivers
- Finds all necessary files (.sys, .dll, .inf, etc.)
- Copies them into the VM's Windows folder
- Organizes files in the correct locations

**When to use:**
- After installing Windows in a VM
- After updating GPU drivers on your host PC
- If GPU isn't working properly in VM

**Requirements:** 
- VM must be powered off
- Windows must be installed in the VM

---

### 5. Complete Setup
Does everything in one workflow: creates VM, assigns GPU, and tries to install drivers.

**What you choose:**
- All the same choices as "Create VM"
- GPU selection and percentage
- Optional Windows ISO

**What it does:**
1. Creates the VM
2. Configures GPU partition
3. Attempts driver installation (skips if Windows not installed yet)

**When to use:** 
- Setting up a brand new VM
- You want the script to do everything automatically

**Note:** If Windows isn't installed yet, you'll need to:
1. Install Windows in Hyper-V Manager
2. Run "Install Drivers" afterward

---

### 6. List VMs
Shows all your VMs in a nice table.

**What you see:**
- VM name and current state (Running/Off)
- RAM, CPU cores, storage size
- GPU allocation percentage (or "None")
- Which GPU is assigned

**When to use:** 
- Quick overview of all your VMs
- Check which VMs have GPU access
- See how much GPU each VM is using

---

### 7. GPU Info
Displays information about GPUs in your computer.

**What you see:**
- GPU name
- Driver version
- Status (OK or error)

**When to use:**
- Check if your GPU is detected
- See current driver version
- Troubleshooting GPU detection issues

---

### 8. Copy Apps
Copies zip files from a "VM Apps" folder into a VM's Downloads folder.

**What you need:**
- Create a folder called **"VM Apps"** in the same location as the script
- Put zip files in that folder (like VB-Cable.zip, Sunshine.zip, etc.)

**What it does:**
- Mounts the VM's hard drive
- Finds the user's Downloads folder
- Copies all zip files there
- Unmounts safely

**When to use:**
- Installing apps/tools that need to be in the VM
- Transferring files without network setup

**Requirements:** 
- VM must be powered off
- Windows must be installed
- At least one user account created in the VM

---

## Common Workflows

### Gaming VM with RTX 4090
1. Run "Complete Setup"
2. Choose "Gaming" preset (16GB, 8 CPU, 256GB)
3. Select RTX 4090
4. Allocate 50% GPU
5. Install Windows in Hyper-V Manager
6. Run "Install Drivers"
7. Start VM and install games!

### Development VM with Multiple GPUs
1. Create first VM, assign GPU #1 at 40%
2. Create second VM, assign GPU #2 at 40%
3. Both VMs can run simultaneously, each with their own GPU

### Updating GPU Drivers
1. Update GPU drivers on your host PC
2. Run script and select "Install Drivers"
3. Choose your VM
4. Script copies the new drivers
5. Start VM - new drivers are active!

---

## Troubleshooting

**Problem:** "No VMs found"
- **Solution:** Create a VM first using "Create VM" or "Complete Setup"

**Problem:** "No partitionable GPUs found"  
- **Solution:** Your GPU may not support partitioning. Check if your GPU drivers are installed.

**Problem:** "Is Windows installed in this VM?"
- **Solution:** The VM disk is empty. Boot the VM and install Windows first.

**Problem:** GPU not showing in VM after driver install
- **Solution:** 
  1. Make sure VM is completely shut down (not saved state)
  2. Run "GPU Partition" to verify GPU is assigned
  3. Run "Install Drivers" again
  4. Start the VM

**Problem:** VM won't start after GPU configuration
- **Solution:** Try reducing GPU allocation to 25-30%

---

## Understanding GPU Allocation

**What do the percentages mean?**
- **25%**: Light use (desktop, basic apps)
- **50%**: Balanced (gaming at medium settings, development)
- **75%**: Heavy use (high-end gaming, 3D rendering)
- **100%**: Maximum (dedicated VM, nothing else using GPU)

**Can I allocate more than 100% total?**
- Yes! Each VM's percentage is of the *total* GPU resources
- Example: Three VMs at 50% each = 150% total = they share as needed

**Do I need to allocate 100% for gaming?**
- No! 50% is usually plenty for 1080p/1440p gaming
- Try 50% first, increase if needed

---

## Tips & Best Practices

1. **Start with 50% GPU allocation** - you can always change it later
2. **Shut down VMs completely** - saved state doesn't work well with GPU-PV
3. **Disable Enhanced Session Mode** - the script does this automatically
4. **Install Windows first** before running driver installation
5. **Update drivers on host, then copy to VM** using "Install Drivers"
6. **Use Generation 2 VMs only** - the script creates these automatically

---

## What About...

**Q: Can I use this with AMD or Intel GPUs?**  
A: Yes! The script detects any GPU automatically.

**Q: Will this slow down my host PC?**  
A: Only when the VM is running and using the GPU. When the VM is off, you have full GPU.

**Q: Can multiple VMs use the GPU at once?**  
A: Yes, if you assign each one a partition. They share the GPU resources.

**Q: Do I need separate GPU for each VM?**  
A: No, one GPU can be partitioned among multiple VMs.

**Q: What if I have multiple GPUs?**  
A: Perfect! You can assign GPU #1 to some VMs and GPU #2 to others.

**Q: Can I change GPU allocation later?**  
A: Yes, run "GPU Partition" again with a different percentage.

**Q: Does this work with laptops?**  
A: Yes, if your laptop GPU supports it (most modern ones do).

---

## Credits

Built using Microsoft's GPU-PV (GPU Paravirtualization) technology for Hyper-V. This script automates the manual configuration process and driver detection that would normally require registry editing and file hunting.

## License

Free to use for personal and educational purposes. No warranty - use at your own risk. Always backup important data before making VM changes.

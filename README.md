# Quick Guide: Hyper-V Gaming VM with GPU Paravirtualization (Partitioning a GPU)

This guide walks you through creating a Hyper-V VM optimized for gaming by using GPU partitioning. It's primarily designed for **Nvidia GPUs** on the host system.

> ⚠️ It *is* possible to use AMD GPUs, but the driver files in Steps **33–36** will differ, and those are not covered here.

---

## ✅ Goal
Allow a VM access to approximately **50% of the GPU's performance**. You can customize this percentage or run multiple VMs if you have the resources.

---

## 🔧 Prerequisites

- Windows 10+ Pro Edition (Host)
- Minimum **16GB RAM** (32+ GB recommended)
- Minimum **6-core CPU** (8+ cores recommended)
- Nvidia GPU with enough headroom to play games below 50% load
- ~256GB free disk space (for larger games like *Vermintide 2*)
- Windows ISO (same version as host — **no Rufus W11 bypass**)

---

## 🪛 Step-by-Step Setup

### Part 1: Enable and Set Up Hyper-V

1. Enable virtualization in UEFI.
2. Open **“Turn Windows features on or off”** from Start.
3. Check and enable **Hyper-V**. Reboot when prompted.
4. Open **Hyper-V Manager**.
5. Right-click your host (left pane) → **Hyper-V Settings**:
   - Disable **Enhanced Session Mode Policy** and **Enhanced Session Mode**.
6. Right-click host → **Virtual Switch Manager**:
   - Create **External Switch**.
   - Assign it to your host network adapter (acts like a physical machine).

---

### Part 2: Create the Virtual Machine

7. Click **New > Virtual Machine**.
8. Name your VM & choose config file location (creates subdirectories).
9. Choose **Generation 2**.
10. Assign RAM (disable Dynamic Memory).
11. Choose the external switch you created (or leave disconnected for Win11 install).
12. Create a **VHD**:
    - Name it, set location, and size (~256GB).
    - VHD is dynamically expanding — it uses only needed space.
13. Choose to install OS from **image**, point to your Windows ISO.
14. Click **Finish** but **do NOT start the VM yet**.

---

### Part 3: Initial VM Configuration

15. Right-click VM → **Settings**:
    - **Firmware**: Ensure ISO/CD is before HDD; Network adapter last.
    - **Security**: Enable Secure Boot and TPM.
    - **Processor**: Set thread count (e.g., 4 threads from a 6C/12T CPU).
    - **Integration Services**: Disable Backup and Guest Services.
    - **Checkpoints**: Disable.
    - **Automatic Start/Stop**: Set to “nothing” and “shutdown” respectively.
16. Apply changes.

---

### Part 4: OS Installation

17. Connect to VM and **start it**. Be quick to boot from ISO.
18. Install Windows:
    - For Windows 11: Use `Shift+F10 > OOBE\BYPASSNRO` to skip MS account.
    - Post-install, connect to the network and update Windows.
    - Name the PC and configure standard settings.
19. **Disable screen blanking** in power settings.

---

### Part 5: Software & Display Setup

20. Install required tools:
    - **VNC** (e.g., TightVNC):  
      `winget install GlavSoft.TightVNC`
    - **VB Cable**:  
      https://vb-audio.com/Cable/
    - **Virtual Display Driver**:  
      https://github.com/itsmikethetech/Virtual-Display-Driver

21. Configure VNC → Reboot VM → **Close Hyper-V window**.  
    > ❗ **Never use Hyper-V RDP to connect again. Use VNC only.**

22. Using VNC, open **Device Manager** → **Disable Hyper-V Display Adapter**.
23. Disable **BitLocker** in Windows settings.
24. Shutdown the VM.

---

### Part 6: GPU Driver Injection

25. On the host, **mount the VM’s VHD** (right-click `.vhdx` → Mount).
26. Open **Disk Management** → assign a drive letter to the largest partition.
27. **Copy Nvidia drivers to VM disk**:
    - Copy the folder:  
      `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64...`  
      → to:  
      `VM C:\Windows\System32\HostDriverStore\FileRepository\`
    - Copy all files in `C:\Windows\System32\` starting with `nv*`  
      → to the same path on the VM disk.

28. In Disk Management, **unmount the VHD**.

---

### Part 7: GPU Partitioning via PowerShell

29. Open **PowerShell ISE as Administrator** on host.
30. In the blue console area, run:
    ```powershell
    Set-ExecutionPolicy unrestricted
    ```
    Confirm with **Y**.

31. In the white script area (click dropdown if hidden), paste:

    > ⚠️ Replace `"Your VM Name"` with your VM's actual name (case-sensitive)

    ```powershell
    $vm = "Your VM Name"
    Remove-VMGpuPartitionAdapter -VMName $vm
    Add-VMGpuPartitionAdapter -VMName $vm

    # VRAM
    Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionVRAM 1
    Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionVRAM 500000000
    Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionVRAM 500000000

    # Encode
    Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionEncode 1
    Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionEncode 500000000
    Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionEncode 500000000

    # Decode
    Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionDecode 1
    Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionDecode 500000000
    Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionDecode 500000000

    # Compute
    Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionCompute 1
    Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionCompute 500000000
    Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionCompute 500000000

    # Additional settings
    Set-VM -GuestControlledCacheTypes $true -VMName $vm
    Set-VM -LowMemoryMappedIoSpace 1Gb -VMName $vm
    Set-VM -HighMemoryMappedIoSpace 32GB -VMName $vm
    ```

32. Click the green **Run Script** button.  
    > 🟡 If you get an error about GPU partition — ignore it, it's normal the first time.

---

### Part 8: Final Setup

33. **Start the VM** → Connect via **VNC**.
34. Install the **Virtual Display Driver**.
35. In **Display Settings**:
    - Set resolution as desired.
    - Set **Display 2 as default**.
    - Choose to **only show on Display 2**.
36. Install **Sunshine**, enable **PIN pairing**.
37. In CMD:
    ```cmd
    cd "C:\Program Files\Sunshine\tools"
    audio-info.exe
    ```
    - Note the **VB-Cable adapter’s ID**.

38. In Sunshine GUI:
    - **Disable** Steam Audio Driver.
    - Manually select **VB-Cable** by ID.
    - Choose the correct **video device**.

39. Disable **Advanced Display Device Options** in Sunshine's Audio/Video settings.
40. Disconnect VNC → Pair Moonlight using PIN.
41. Connect using **Moonlight**.
    > 🔄 The first few attempts may show “No Video Received.” Retry until it connects (usually 1–3 tries).

---

## 📝 Notes

- Every time you **update GPU drivers on the host**, you must **repeat steps 33–36** (delete old NV files and recopy them to the VM).
